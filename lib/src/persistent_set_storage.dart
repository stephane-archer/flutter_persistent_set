import 'dart:async';

import 'package:meta/meta.dart' show internal;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import 'persistent_set_coordination.dart';

/// Storage used by [PersistentSet].
///
/// [transaction] must serialize callbacks that target the same logical backend
/// and key, including callbacks made through different storage handles. Before
/// invoking the callback, it must load the latest available value into the
/// supplied [PersistentSetStorageTransaction]. It must invoke the callback
/// exactly once and keep the transaction locked until the callback's
/// synchronous or asynchronous result completes, including when it fails.
///
/// [read] is a synchronous view of the last value observed by this storage
/// handle. It must not perform platform I/O. Use [transaction] when an
/// authoritative asynchronous read is needed. Values returned by either read
/// method must be detached snapshots or otherwise safe for the caller to
/// mutate without changing storage.
///
/// Writes and removals are intentionally available only through
/// [PersistentSetStorageTransaction], so callers cannot bypass the transaction
/// boundary. An implementation that retains values passed to
/// [PersistentSetStorageTransaction.write] must
/// snapshot them before the returned future completes.
abstract interface class PersistentSetStorage {
  List<String>? read(String key);

  Future<R> transaction<R>(
    String key,
    FutureOr<R> Function(PersistentSetStorageTransaction transaction) action,
  );
}

/// Access to one key while a [PersistentSetStorage.transaction] is held.
abstract interface class PersistentSetStorageTransaction {
  /// The latest value loaded before the transaction callback started.
  List<String>? read();

  Future<bool> write(List<String> values);

  Future<bool> remove();
}

/// A [PersistentSetStorage] backed by `shared_preferences`.
///
/// [create] uses [SharedPreferencesAsync], avoiding the optimistic global cache
/// used by the legacy [SharedPreferences] API. It selects Android's legacy
/// SharedPreferences backend and the `flutter.` key prefix by default so data
/// written by earlier package versions remains available. Async and legacy
/// adapters with the same prefix share an isolate-local, per-key transaction
/// coordinator.
///
/// The legacy-backed constructor is used internally when callers inject a
/// [SharedPreferences] instance. It serializes all operations that share that
/// instance and reloads its cache after failures. Direct writes through that
/// same legacy instance are outside the coordinator and therefore should not
/// run concurrently with transactions through this adapter. Because the
/// legacy API reloads one process-wide cache, its transaction callbacks cannot
/// start another transaction through a bundled SharedPreferences adapter.
@internal
final class SharedPreferencesPersistentSetStorage
    implements PersistentSetStorage {
  static final PersistentStorageCoordinator _sharedCoordinator =
      PersistentStorageCoordinator();
  static final Expando<StorageOperationQueue> _legacyOperationQueues =
      Expando<StorageOperationQueue>();

  final _SharedPreferencesBackend _backend;
  final StorageOperationQueue? _allKeysQueue;
  final Map<String, List<String>?> _observedValues = {};

  SharedPreferencesPersistentSetStorage(
    final SharedPreferences preferences, {
    final String keyPrefix = 'flutter.',
  }) : _backend = _LegacySharedPreferencesBackend(preferences, keyPrefix),
       _allKeysQueue =
           _legacyOperationQueues[preferences] ??= StorageOperationQueue(
             allowReentrant: true,
           );

  SharedPreferencesPersistentSetStorage._async(
    final SharedPreferencesAsync preferences,
    final String keyPrefix,
  ) : _backend = _AsyncSharedPreferencesBackend(preferences, keyPrefix),
      _allKeysQueue = null;

  static Future<SharedPreferencesPersistentSetStorage> create({
    final String keyPrefix = 'flutter.',
  }) async {
    const options = SharedPreferencesAsyncAndroidOptions(
      backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
      originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
        fileName: 'FlutterSharedPreferences',
      ),
    );
    return SharedPreferencesPersistentSetStorage._async(
      SharedPreferencesAsync(options: options),
      keyPrefix,
    );
  }

  @override
  List<String>? read(final String key) {
    return _observedValues.containsKey(key)
        ? _copyStrings(_observedValues[key])
        : _backend.readCached(key);
  }

  @override
  Future<R> transaction<R>(
    final String key,
    final FutureOr<R> Function(PersistentSetStorageTransaction transaction)
    action,
  ) {
    final legacyContext = Zone.current[_legacyTransactionZoneKey];
    if (legacyContext is _LegacyTransactionContext && legacyContext.isActive) {
      throw StateError(
        'Cannot start a nested SharedPreferences transaction while a legacy '
        'SharedPreferences transaction is locked.',
      );
    }

    final coordinationKey = _backend.coordinationKey(key);

    Future<R> runTransaction() async {
      final current = await _backend.read(key);
      _record(key, current);
      final transaction = _SharedPreferencesStorageTransaction(
        key,
        current,
        _backend,
        (final values) => _record(key, values),
      );
      if (_allKeysQueue == null) {
        return action(transaction);
      }

      final context = _LegacyTransactionContext();
      try {
        return await runZoned(
          () => Future<R>.sync(() => action(transaction)),
          zoneValues: {_legacyTransactionZoneKey: context},
        );
      } finally {
        context.isActive = false;
      }
    }

    return _sharedCoordinator.run(coordinationKey, () {
      final allKeysQueue = _allKeysQueue;
      return allKeysQueue == null
          ? runTransaction()
          : allKeysQueue.run(runTransaction);
    });
  }

  void _record(final String key, final List<String>? values) {
    _observedValues[key] = _copyStrings(values);
  }
}

final Object _legacyTransactionZoneKey = Object();

final class _LegacyTransactionContext {
  var isActive = true;
}

abstract interface class _SharedPreferencesBackend {
  String coordinationKey(String key);

  List<String>? readCached(String key);

  Future<List<String>?> read(String key);

  Future<bool> write(String key, List<String> values);

  Future<bool> remove(String key);
}

final class _AsyncSharedPreferencesBackend
    implements _SharedPreferencesBackend {
  final SharedPreferencesAsync _preferences;
  final String _keyPrefix;

  _AsyncSharedPreferencesBackend(this._preferences, this._keyPrefix);

  String _storageKey(final String key) => '$_keyPrefix$key';

  @override
  String coordinationKey(final String key) => _storageKey(key);

  @override
  List<String>? readCached(final String key) => null;

  @override
  Future<List<String>?> read(final String key) async {
    final values = await _preferences.getStringList(_storageKey(key));
    return values == null ? null : List<String>.of(values, growable: false);
  }

  @override
  Future<bool> write(final String key, final List<String> values) async {
    await _preferences.setStringList(_storageKey(key), values);
    return true;
  }

  @override
  Future<bool> remove(final String key) async {
    await _preferences.remove(_storageKey(key));
    return true;
  }
}

final class _LegacySharedPreferencesBackend
    implements _SharedPreferencesBackend {
  final SharedPreferences _preferences;
  final String _keyPrefix;

  _LegacySharedPreferencesBackend(this._preferences, this._keyPrefix);

  @override
  String coordinationKey(final String key) => '$_keyPrefix$key';

  @override
  List<String>? readCached(final String key) => _preferences.getStringList(key);

  @override
  Future<List<String>?> read(final String key) async {
    await _preferences.reload();
    return _preferences.getStringList(key);
  }

  @override
  Future<bool> write(final String key, final List<String> values) {
    return _runWithCacheRollback(() => _preferences.setStringList(key, values));
  }

  @override
  Future<bool> remove(final String key) {
    return _runWithCacheRollback(() => _preferences.remove(key));
  }

  Future<bool> _runWithCacheRollback(
    final Future<bool> Function() operation,
  ) async {
    Object? operationError;
    StackTrace? operationStackTrace;
    var succeeded = false;

    try {
      succeeded = await operation();
    } on Object catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }

    if (succeeded) {
      return true;
    }

    try {
      await _preferences.reload();
    } on Object catch (error, stackTrace) {
      if (operationError == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    if (operationError != null) {
      Error.throwWithStackTrace(operationError, operationStackTrace!);
    }
    return false;
  }
}

final class _SharedPreferencesStorageTransaction
    implements PersistentSetStorageTransaction {
  final String _key;
  final _SharedPreferencesBackend _backend;
  final void Function(List<String>? values) _record;
  List<String>? _current;

  _SharedPreferencesStorageTransaction(
    this._key,
    final List<String>? current,
    this._backend,
    this._record,
  ) : _current = _copyStrings(current);

  @override
  List<String>? read() => _copyStrings(_current);

  @override
  Future<bool> write(final List<String> values) async {
    final snapshot = List<String>.of(values, growable: false);
    if (!await _backend.write(_key, snapshot)) {
      return false;
    }
    _current = snapshot;
    _record(snapshot);
    return true;
  }

  @override
  Future<bool> remove() async {
    if (!await _backend.remove(_key)) {
      return false;
    }
    _current = null;
    _record(null);
    return true;
  }
}

List<String>? _copyStrings(final List<String>? values) {
  return values == null ? null : List<String>.of(values, growable: false);
}
