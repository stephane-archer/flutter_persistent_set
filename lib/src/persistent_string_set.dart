import 'package:shared_preferences/shared_preferences.dart';

import 'persistent_set_collection.dart';
import 'persistent_set_storage.dart';

class PersistentStringSet extends PersistentSet<String> {
  PersistentStringSet._(
    final String key,
    final Set<String> mem,
    final PersistentSetStorage storage,
    final Iterable<String> encodedValues,
  ) : super.internalWithStorage(
        key,
        mem,
        storage,
        (s) => s,
        (s) => s,
        encodedValues: encodedValues,
      );

  /// Create or load a persistent set of strings at `key`.
  /// If the key does not exist and [seedIfMissing] is provided, it will be used
  /// to initialize the set and persist it immediately.
  ///
  /// [seedIfEmpty] is deprecated. It retains the 0.1 behavior of seeding both
  /// missing keys and existing empty sets; use [seedIfMissing] for new code.
  ///
  /// By default, persistence uses [SharedPreferencesAsync]. Pass [storage] to
  /// use another transactional backend. Alternatively, pass a legacy
  /// [SharedPreferences] instance through [preferences] in tests, including
  /// tests configured with [SharedPreferences.setMockInitialValues].
  /// [storage] and [preferences] cannot both be provided.
  /// When [storage] is provided, it owns its key namespace and [keyPrefix] is
  /// not applied by [PersistentStringSet].
  /// Pass the prefix previously configured through
  /// `SharedPreferences.setPrefix` as [keyPrefix] when it was not `flutter.`.
  static Future<PersistentStringSet> create(
    final String key, {
    final Set<String>? seedIfMissing,
    @Deprecated('Use seedIfMissing for missing-key-only seeding.')
    final Set<String>? seedIfEmpty,
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
      seedIfMissing: seedIfMissing,
      seedIfEmpty: seedIfEmpty,
      storage: resolvedStorage,
    );
  }

  static Future<PersistentStringSet> _create(
    final String key, {
    final Set<String>? seedIfMissing,
    final Set<String>? seedIfEmpty,
    required final PersistentSetStorage storage,
  }) async {
    if (seedIfMissing != null && seedIfEmpty != null) {
      throw ArgumentError(
        'seedIfMissing and seedIfEmpty cannot both be provided.',
      );
    }

    final mem = <String>{};
    final encodedValues = <String>[];
    await storage.transaction(key, (final transaction) async {
      final list = transaction.read();

      Future<void> persistSeed(final Set<String> seed) async {
        mem.addAll(seed);
        encodedValues.addAll(mem);
        if (!await transaction.write(encodedValues)) {
          throw PersistentSetPersistenceException(key: key, operation: 'write');
        }
      }

      if (list != null) {
        for (final value in list) {
          if (mem.add(value)) {
            encodedValues.add(value);
          }
        }
      }

      if (list == null && seedIfMissing != null) {
        await persistSeed(seedIfMissing);
      } else if (mem.isEmpty && seedIfEmpty?.isNotEmpty == true) {
        await persistSeed(seedIfEmpty!);
      }
    });
    return PersistentStringSet._(key, mem, storage, encodedValues);
  }
}
