import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart' show internal, protected, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'persistent_set_storage.dart';

/// Thrown when the storage backend reports that a mutation was not saved.
final class PersistentSetPersistenceException implements Exception {
  final String key;
  final String operation;

  const PersistentSetPersistenceException({
    required this.key,
    required this.operation,
  });

  @override
  String toString() {
    return 'PersistentSetPersistenceException: $operation failed for "$key"';
  }
}

/// A set whose encoded values are persisted after each successful mutation.
///
/// Values should be treated as immutable while they are stored. In particular,
/// changing fields used by `==` or `hashCode` violates the contract of [Set].
/// The codecs are part of the persisted data schema and must be deterministic.
/// For every stored value, `from(to(value))` must compare equal to `value` and
/// have a compatible `hashCode`. Distinct values that may coexist in the set
/// must encode to distinct strings. Changing a codec requires retaining support
/// for existing encodings or migrating the stored values.
class PersistentSet<T> {
  final String _key;
  final Set<T> _mem;
  final PersistentSetStorage _storage;
  final String Function(T value) _to;
  final T Function(String encoded) _from;
  List<String>? _memoryEncoding;
  bool _memoryEncodingNeedsInference;

  /// Internal constructor for use when the set is already loaded.
  /// Use [create] to create or load a persistent set.
  /// This is used for subclassing (for example, `PersistentStringSet`).
  /// Pass the prefix configured through `SharedPreferences.setPrefix` when it
  /// is not the default `flutter.` value.
  @protected
  PersistentSet.internal(
    this._key,
    this._mem,
    final SharedPreferences preferences,
    this._to,
    this._from, {
    final String keyPrefix = 'flutter.',
  }) : _storage = SharedPreferencesPersistentSetStorage(
         preferences,
         keyPrefix: keyPrefix,
       ),
       _memoryEncoding = null,
       _memoryEncodingNeedsInference = true;

  @internal
  PersistentSet.internalWithStorage(
    this._key,
    this._mem,
    this._storage,
    this._to,
    this._from, {
    final Iterable<String>? encodedValues,
  }) : _memoryEncoding =
           encodedValues == null ? null : _alignedEncoding(_mem, encodedValues),
       _memoryEncodingNeedsInference = encodedValues == null;

  int get length => _mem.length;

  bool contains(T? element) => _mem.contains(element);

  /// Set.lookup preserves the actual stored instance (useful if T overrides ==).
  T? lookup(T? element) => _mem.lookup(element);

  /// Access a copy of the set.
  ///
  /// The deprecated [reload] option reads the latest value already observed by
  /// this storage handle but cannot perform platform I/O synchronously.
  /// Use `await set.reload()` when changes may have come from another isolate,
  /// process, or an external writer.
  Set<T> toSet({
    @Deprecated('Use await reload() for an authoritative storage read.')
    final bool reload = false,
  }) {
    return reload
        ? _decodeMembership(_storage.read(_key)).values
        : _mem.toSet();
  }

  /// Reloads the latest persisted membership and updates this instance.
  Future<Set<T>> reload() {
    return _serializeMutation((final transaction) async {
      final current = _decodeMembership(transaction.read());
      _replaceMemory(current.values, encodedValues: current.encodedValues);
      return _mem.toSet();
    });
  }

  /// Runs [mutation] against a membership draft.
  ///
  /// Mutations that use the same storage coordinator and key are serialized,
  /// including mutations from different [PersistentSet] instances. Each
  /// mutation starts from the latest persisted membership, preventing stale
  /// instances from overwriting previously committed values.
  ///
  /// The draft is written at most once and becomes visible through this instance
  /// only after the storage operation completes successfully. Existing instances
  /// are not live views; call [reload] to update an instance after another one
  /// commits.
  ///
  /// The draft is a shallow copy created by [Set.toSet]: it has independent
  /// membership but contains the refreshed set's element instances. Elements
  /// whose encoded values have not changed reuse their existing in-memory
  /// instances; new or changed encoded values are decoded. The draft preserves
  /// the equality and ordering semantics of standard Dart set implementations.
  /// Sets created through [create] are insertion ordered. Treat elements as
  /// immutable and change the draft only through [Set] operations.
  /// Transactional rollback covers membership and iteration order, not
  /// mutations made to element objects themselves.
  ///
  /// The storage transaction remains locked until [mutation] and its storage
  /// operation complete. Keep asynchronous work short, resolve independent data
  /// before calling [mutate] when practical. Re-entering the same storage and key
  /// before this callback completes throws a [StateError]. The default async
  /// storage permits nested transactions for distinct keys when they are
  /// acquired in lexicographically ascending order; this deterministic ordering
  /// prevents dependency cycles. The injected legacy `SharedPreferences`
  /// adapter does not permit nested bundled-storage transactions because it
  /// must serialize reloads of the API's whole cache. Apply changes for this
  /// set to the provided draft.
  ///
  /// Do not retain the draft.
  Future<R> mutate<R>(final FutureOr<R> Function(Set<T> draft) mutation) {
    return _serializeMutation((final transaction) async {
      final currentRaw = transaction.read();
      final current = _decodeMembership(currentRaw);
      final before = currentRaw ?? const <String>[];
      final draft = current.values.toSet();
      final result = await mutation(draft);
      await _commitDraft(transaction, draft, before: before);
      return result;
    });
  }

  /// Add [value] to the set. Returns true if the value was not already present.
  /// If the set was modified, it is persisted immediately.
  Future<bool> add(final T value) {
    return _mutateMembership(
      shouldChange: (final current) => !current.contains(value),
      mutation: (final draft) => draft.add(value),
    );
  }

  /// Add all [values] to the set. If the set was modified, it is persisted
  /// immediately.
  /// If [values] is empty or all values are already present, no write occurs.
  /// This method is more efficient than calling [add] repeatedly.
  Future<void> addAll(final Iterable<T> values) async {
    final candidates = values.toList(growable: false);
    late List<T> additions;
    await _mutateMembership(
      shouldChange: (final current) {
        additions = [
          for (final value in candidates)
            if (!current.contains(value)) value,
        ];
        return additions.isNotEmpty;
      },
      mutation: (final draft) => draft.addAll(additions),
    );
  }

  /// Remove [value] from the set. Returns true if the value was present.
  /// If the set was modified, it is persisted immediately.
  /// If [value] is null, does nothing and returns false.
  Future<bool> remove(final T? value) {
    return _mutateMembership(
      shouldChange: (final current) => current.contains(value),
      mutation: (final draft) => draft.remove(value),
    );
  }

  /// Remove all elements that match the given [test].
  /// If the set was modified, it is persisted immediately.
  /// If no elements match, no write occurs.
  Future<void> removeWhere(final bool Function(T) test) {
    late List<T> removals;
    return _mutateMembership(
      shouldChange: (final current) {
        removals = current.where(test).toList(growable: false);
        return removals.isNotEmpty;
      },
      mutation: (final draft) => draft.removeAll(removals),
    ).then<void>((final _) {});
  }

  /// Remove all elements from the set and remove its storage key.
  Future<void> clear() {
    return _serializeMutation((final transaction) async {
      if (!await transaction.remove()) {
        throw PersistentSetPersistenceException(key: _key, operation: 'remove');
      }
      _mem.clear();
      _memoryEncoding = const <String>[];
    });
  }

  Future<bool> _mutateMembership({
    required final bool Function(Set<T> current) shouldChange,
    required final void Function(Set<T> draft) mutation,
  }) {
    return _serializeMutation((final transaction) async {
      final currentRaw = transaction.read();
      final current = _decodeMembership(currentRaw);
      if (!shouldChange(current.values)) {
        _replaceMemory(current.values, encodedValues: current.encodedValues);
        return false;
      }
      final before = currentRaw ?? const <String>[];
      final draft = current.values.toSet();
      mutation(draft);
      await _commitDraft(transaction, draft, before: before);
      return true;
    });
  }

  Future<void> _commitDraft(
    final PersistentSetStorageTransaction transaction,
    final Set<T> draft, {
    required final List<String> before,
  }) async {
    final after = _encode(draft);

    if (!_sameValues(before, after) && !await transaction.write(after)) {
      throw PersistentSetPersistenceException(key: _key, operation: 'write');
    }

    _replaceMemory(draft, encodedValues: after);
  }

  void _replaceMemory(
    final Iterable<T> values, {
    required final Iterable<String>? encodedValues,
  }) {
    final valueSnapshot = List<T>.of(values, growable: false);
    final encodingSnapshot =
        encodedValues == null
            ? null
            : List<String>.of(encodedValues, growable: false);
    _mem
      ..clear()
      ..addAll(valueSnapshot);
    _memoryEncoding =
        encodingSnapshot == null
            ? null
            : _reorderEncoding(valueSnapshot, encodingSnapshot, _mem);
    _memoryEncodingNeedsInference = false;
  }

  List<String> _encode(final Iterable<T> values) {
    return values.map(_to).toList(growable: false);
  }

  _DecodedMembership<T> _decodeMembership(final List<String>? raw) {
    final encodedValues = raw ?? const <String>[];
    final result = _mem.toSet()..clear();
    if (_memoryEncodingNeedsInference) {
      _memoryEncoding = _inferAlignedEncoding(_mem, encodedValues, _to);
      _memoryEncodingNeedsInference = false;
    }
    final memoryEncoding = _memoryEncoding;

    final reusableValues = <String, ListQueue<T>>{};
    if (memoryEncoding != null && memoryEncoding.length == _mem.length) {
      var index = 0;
      for (final value in _mem) {
        (reusableValues[memoryEncoding[index]] ??= ListQueue<T>()).add(value);
        index += 1;
      }
    }

    final acceptedValues = <T>[];
    final acceptedEncodings = <String>[];
    for (final encoded in encodedValues) {
      final reusable = reusableValues[encoded];
      final value =
          reusable == null || reusable.isEmpty
              ? _from(encoded)
              : reusable.removeFirst();
      if (result.add(value)) {
        acceptedValues.add(value);
        acceptedEncodings.add(encoded);
      }
    }
    return _DecodedMembership(
      result,
      _reorderEncoding(acceptedValues, acceptedEncodings, result),
    );
  }

  Future<R> _serializeMutation<R>(
    final Future<R> Function(PersistentSetStorageTransaction transaction)
    mutation,
  ) {
    final currentContext = Zone.current[_persistentSetMutationZoneKey];
    if (currentContext is _MutationContext &&
        currentContext.isActive &&
        currentContext.holds(_storage, _key)) {
      throw StateError(
        'Cannot re-enter a PersistentSet mutation for the same storage and '
        'key. Finish the active callback first and mutate its provided draft '
        'instead.',
      );
    }

    return _storage.transaction(
      _key,
      (final transaction) =>
          _runInMutationZone(_storage, _key, () => mutation(transaction)),
    );
  }

  Future<R> _runInMutationZone<R>(
    final PersistentSetStorage storage,
    final String key,
    final Future<R> Function() mutation,
  ) async {
    final parent = Zone.current[_persistentSetMutationZoneKey];
    final context = _MutationContext(
      storage,
      key,
      parent: parent is _MutationContext && parent.isActive ? parent : null,
    );
    try {
      return await runZoned(
        mutation,
        zoneValues: {_persistentSetMutationZoneKey: context},
      );
    } finally {
      context.isActive = false;
    }
  }

  /// Create or load a persistent set at `key`.
  /// You must provide functions to convert between T and String.
  /// If T is String, use (s) => s for both [to] and
  /// [from] (see `PersistentStringSet`).
  /// The codecs must be deterministic and preserve set equality:
  /// `from(to(value))` must compare equal to `value` with a compatible
  /// `hashCode`, and distinct values that may coexist must have distinct
  /// encodings. Existing encodings must remain readable across app versions or
  /// be migrated when the codecs change.
  /// If the key does not exist and [seedIfMissing] is provided, it will
  /// be used to initialize the set and persist it immediately.
  ///
  /// [seedIfEmpty] is a deprecated compatibility alias. For
  /// [PersistentSet], it has always seeded only a missing key.
  ///
  /// By default, persistence uses [SharedPreferencesAsync]. Pass [storage] to
  /// use another transactional backend. Alternatively, pass a legacy
  /// [SharedPreferences] instance through [preferences] in tests, including
  /// tests configured with [SharedPreferences.setMockInitialValues].
  /// [storage] and [preferences] cannot both be provided.
  /// When [storage] is provided, it owns its key namespace and [keyPrefix] is
  /// not applied by [PersistentSet].
  /// Pass the prefix previously configured through
  /// `SharedPreferences.setPrefix` as [keyPrefix] when it was not `flutter.`.
  static Future<PersistentSet<T>> create<T>(
    final String key, {
    required final String Function(T value) to,
    required final T Function(String encoded) from,
    final Iterable<T>? seedIfMissing,
    @Deprecated('Use seedIfMissing instead.') final Iterable<T>? seedIfEmpty,
    final PersistentSetStorage? storage,
    final SharedPreferences? preferences,
    final String keyPrefix = 'flutter.',
  }) async {
    final resolvedStorage = await resolvePersistentSetStorage(
      storage: storage,
      preferences: preferences,
      keyPrefix: keyPrefix,
    );
    return _create(
      key,
      to: to,
      from: from,
      seedIfMissing: seedIfMissing,
      seedIfEmpty: seedIfEmpty,
      storage: resolvedStorage,
    );
  }

  static Future<PersistentSet<T>> _create<T>(
    final String key, {
    required final String Function(T value) to,
    required final T Function(String encoded) from,
    final Iterable<T>? seedIfMissing,
    final Iterable<T>? seedIfEmpty,
    required final PersistentSetStorage storage,
  }) async {
    if (seedIfMissing != null && seedIfEmpty != null) {
      throw ArgumentError(
        'seedIfMissing and seedIfEmpty cannot both be provided.',
      );
    }

    final seed = seedIfMissing ?? seedIfEmpty;
    final mem = <T>{};
    final encodedValues = <String>[];

    await storage.transaction(key, (final transaction) async {
      final raw = transaction.read();
      if (raw != null) {
        for (final encoded in raw) {
          if (mem.add(from(encoded))) {
            encodedValues.add(encoded);
          }
        }
      } else if (seed != null) {
        mem.addAll(seed);
        encodedValues.addAll(mem.map(to));
        if (!await transaction.write(encodedValues)) {
          throw PersistentSetPersistenceException(key: key, operation: 'write');
        }
      }
    });

    return PersistentSet.internalWithStorage(
      key,
      mem,
      storage,
      to,
      from,
      encodedValues: encodedValues,
    );
  }
}

@internal
Future<PersistentSetStorage> resolvePersistentSetStorage({
  required final PersistentSetStorage? storage,
  required final SharedPreferences? preferences,
  required final String keyPrefix,
}) async {
  if (storage != null && preferences != null) {
    throw ArgumentError('storage and preferences cannot both be provided.');
  }
  if (storage != null) {
    return storage;
  }
  return preferences == null
      ? SharedPreferencesPersistentSetStorage.create(keyPrefix: keyPrefix)
      : SharedPreferencesPersistentSetStorage(
        preferences,
        keyPrefix: keyPrefix,
      );
}

@visibleForTesting
PersistentSet<T> persistentSetFromMemory<T>(
  final String key,
  final Set<T> values,
  final PersistentSetStorage storage, {
  required final String Function(T value) to,
  required final T Function(String encoded) from,
}) {
  return PersistentSet.internalWithStorage(key, values, storage, to, from);
}

final class _DecodedMembership<T> {
  final Set<T> values;
  final List<String>? encodedValues;

  const _DecodedMembership(this.values, this.encodedValues);
}

final class _MutationContext {
  final PersistentSetStorage storage;
  final String key;
  final _MutationContext? parent;
  var isActive = true;

  _MutationContext(this.storage, this.key, {this.parent});

  bool holds(final PersistentSetStorage candidateStorage, final String key) {
    for (
      _MutationContext? context = this;
      context != null;
      context = context.parent
    ) {
      if (context.isActive &&
          identical(context.storage, candidateStorage) &&
          context.key == key) {
        return true;
      }
    }
    return false;
  }
}

final Object _persistentSetMutationZoneKey = Object();

List<String>? _alignedEncoding<T>(
  final Set<T> values,
  final Iterable<String>? encodedValues,
) {
  if (encodedValues == null) {
    return values.isEmpty ? const <String>[] : null;
  }
  final snapshot = List<String>.of(encodedValues, growable: false);
  return snapshot.length == values.length ? snapshot : null;
}

List<String>? _inferAlignedEncoding<T>(
  final Set<T> values,
  final Iterable<String>? encodedValues,
  final String Function(T value) encode,
) {
  if (encodedValues == null) {
    return values.isEmpty ? const <String>[] : null;
  }

  final remaining = <String, int>{};
  var encodedValueCount = 0;
  for (final encoded in encodedValues) {
    remaining.update(encoded, (final count) => count + 1, ifAbsent: () => 1);
    encodedValueCount += 1;
  }
  if (encodedValueCount != values.length) {
    return null;
  }

  final aligned = <String>[];
  for (final value in values) {
    final encoded = encode(value);
    final count = remaining[encoded];
    if (count == null) {
      return null;
    }
    aligned.add(encoded);
    if (count == 1) {
      remaining.remove(encoded);
    } else {
      remaining[encoded] = count - 1;
    }
  }
  return remaining.isEmpty ? List<String>.of(aligned, growable: false) : null;
}

List<String>? _reorderEncoding<T>(
  final List<T> sourceValues,
  final List<String> sourceEncoding,
  final Iterable<T> targetValues,
) {
  if (sourceValues.length != sourceEncoding.length) {
    return null;
  }

  final encodingByIdentity = HashMap<T, String>.identity();
  for (var index = 0; index < sourceValues.length; index += 1) {
    encodingByIdentity[sourceValues[index]] = sourceEncoding[index];
  }
  if (encodingByIdentity.length != sourceValues.length) {
    return null;
  }

  final aligned = <String>[];
  for (final value in targetValues) {
    if (!encodingByIdentity.containsKey(value)) {
      return null;
    }
    aligned.add(encodingByIdentity[value]!);
  }
  return aligned.length == sourceEncoding.length
      ? List<String>.of(aligned, growable: false)
      : null;
}

bool _sameValues(final List<String> first, final List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
