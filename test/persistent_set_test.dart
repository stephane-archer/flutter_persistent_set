import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:persistent_set/persistent_set.dart';
import 'package:persistent_set/persistent_set_storage.dart';
import 'package:persistent_set/src/persistent_set_collection.dart'
    show persistentSetFromMemory;
import 'package:persistent_set/src/persistent_set_storage.dart'
    show SharedPreferencesPersistentSetStorage;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'test_preferences.dart';

Future<PersistentSet<T>> _createPersistentSet<T>(
  final String key, {
  required final String Function(T value) to,
  required final T Function(String encoded) from,
  final Iterable<T>? seedIfMissing,
  final Iterable<T>? seedIfEmpty,
  final PersistentSetStorage? storage,
}) {
  return PersistentSet.create(
    key,
    to: to,
    from: from,
    seedIfMissing: seedIfMissing,
    // ignore: deprecated_member_use_from_same_package
    seedIfEmpty: seedIfEmpty,
    storage: storage,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Reset prefs before each test.
    setMockInitialPreferences({});
  });

  group('PersistentSet.create', () {
    test('supports the standard legacy SharedPreferences test mock', () async {
      const key = 'mocked_strings';
      SharedPreferences.setMockInitialValues({
        key: <String>['mocked'],
      });
      final preferences = await SharedPreferences.getInstance();

      final set = await PersistentSet.create<String>(
        key,
        to: (final value) => value,
        from: (final encoded) => encoded,
        preferences: preferences,
      );

      expect(set.toSet(), {'mocked'});
      await set.add('written');
      expect(preferences.getStringList(key), ['mocked', 'written']);
    });

    test('rejects custom storage with legacy preferences', () async {
      final preferences = await SharedPreferences.getInstance();

      expect(
        () => PersistentSet.create<String>(
          'ambiguous-storage',
          to: (final value) => value,
          from: (final encoded) => encoded,
          storage: _FakePersistentSetStorage(),
          preferences: preferences,
        ),
        throwsArgumentError,
      );
    });

    test('applies a custom key prefix to the default async storage', () async {
      const key = 'custom-prefix';
      const prefixedKey = 'application.$key';
      setMockInitialPreferences({
        prefixedKey: <String>['existing'],
      });

      final set = await PersistentSet.create<String>(
        key,
        to: (final value) => value,
        from: (final encoded) => encoded,
        keyPrefix: 'application.',
      );

      expect(set.toSet(), {'existing'});
      await set.add('written');

      final preferences = SharedPreferencesAsync();
      expect(await preferences.getStringList(prefixedKey), [
        'existing',
        'written',
      ]);
      expect(await preferences.getStringList('flutter.$key'), isNull);
    });

    test('loads existing values', () async {
      setMockInitialPreferences({
        'ints': ['1', '2', '3'],
      });

      final s = await _createPersistentSet<int>(
        'ints',
        to: (v) => v.toString(),
        from: int.parse,
      );

      expect(s.length, 3);
      expect(s.contains(1), true);
      expect(s.contains(2), true);
      expect(s.contains(3), true);
    });

    test('creates empty when no existing and no seed', () async {
      final s = await _createPersistentSet<String>(
        'strings',
        to: (v) => v,
        from: (s) => s,
      );
      expect(s.length, 0);
    });

    test('seeds when missing and persists immediately', () async {
      final seed = <String>{'a', 'b'};
      final s = await _createPersistentSet<String>(
        'seeded',
        to: (v) => v,
        from: (s) => s,
        seedIfMissing: seed,
      );
      expect(s.length, seed.length);
      expect(s.contains('a'), true);
      expect(s.contains('b'), true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('seeded')!.toSet(), seed);
    });

    test('deprecated seedIfEmpty remains a missing-key alias', () async {
      final set = await _createPersistentSet<String>(
        'legacy-seed',
        to: (value) => value,
        from: (value) => value,
        // ignore: deprecated_member_use_from_same_package
        seedIfEmpty: {'legacy'},
      );

      expect(set.toSet(), {'legacy'});
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('legacy-seed'), ['legacy']);
    });

    test(
      'deprecated seedIfEmpty does not replace an existing empty set',
      () async {
        setMockInitialPreferences({'legacy-empty': <String>[]});

        final set = await _createPersistentSet<String>(
          'legacy-empty',
          to: (value) => value,
          from: (value) => value,
          // ignore: deprecated_member_use_from_same_package
          seedIfEmpty: {'legacy'},
        );

        expect(set.toSet(), isEmpty);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getStringList('legacy-empty'), isEmpty);
      },
    );

    test('rejects both seed parameter names', () async {
      expect(
        () => _createPersistentSet<String>(
          'ambiguous-seed',
          to: (value) => value,
          from: (value) => value,
          seedIfMissing: {'new'},
          // ignore: deprecated_member_use_from_same_package
          seedIfEmpty: {'legacy'},
        ),
        throwsArgumentError,
      );
    });
  });

  test('protected constructor defers encoder calls until refresh', () async {
    const key = 'subclass-construction';
    setMockInitialPreferences({
      key: <String>['stored'],
    });
    final preferences = await SharedPreferences.getInstance();
    var constructionComplete = false;

    final set = _PersistentSetSubclass(key, {'stored'}, preferences, (
      final value,
    ) {
      if (!constructionComplete) {
        throw StateError('encoder called during construction');
      }
      return value;
    });
    constructionComplete = true;

    expect((await set.reload()).toList(), ['stored']);
  });

  group('Mutations persist correctly', () {
    test('add() adds and persists; duplicate add() returns false', () async {
      final s = await _createPersistentSet<int>(
        'k1',
        to: (v) => v.toString(),
        from: int.parse,
      );

      final first = await s.add(42);
      expect(first, true);
      expect(s.length, 1);

      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('k1'), ['42']);

      final dup = await s.add(42);
      expect(dup, false);
      expect(s.length, 1);
      // Still the same persisted list.
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('k1'), ['42']);
    });

    test('addAll() persists only when size changes', () async {
      final s = await _createPersistentSet<String>(
        'k2',
        to: (v) => v,
        from: (s) => s,
      );

      await s.addAll(['x', 'y']); // adds 2
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('k2')!.toSet(), {'x', 'y'});

      // Adding values already present should leave storage unchanged.
      await s.addAll(['x']);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('k2')!.toSet(), {'x', 'y'});

      // Adding a new value should persist again.
      await s.addAll(['z']);
      prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getStringList('k2')!.toSet(), {'x', 'y', 'z'});
    });

    test('addAll() snapshots its iterable when invoked', () async {
      final storage = _FakePersistentSetStorage();
      final s = await _createPersistentSet<String>(
        'add-all-snapshot',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );
      final values = ['first'];

      final addition = s.addAll(values);
      values.add('late');
      await addition;

      expect(s.toSet().toList(), ['first']);
      expect(storage.values, ['first']);
    });

    test(
      'remove() removes existing value and persists, returns false if missing',
      () async {
        setMockInitialPreferences({
          'k3': ['1', '2'],
        });
        final s = await _createPersistentSet<int>(
          'k3',
          to: (v) => v.toString(),
          from: int.parse,
        );

        final removed = await s.remove(1);
        expect(removed, true);
        expect(s.contains(1), false);

        var prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('k3'), ['2']);

        final removedMissing = await s.remove(99);
        expect(removedMissing, false);
        // Still ['2'] in prefs
        prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('k3'), ['2']);
      },
    );

    test(
      'removeWhere() removes matching entries and persists only if changed',
      () async {
        setMockInitialPreferences({
          'k4': ['1', '2', '3', '4'],
        });
        final s = await _createPersistentSet<int>(
          'k4',
          to: (v) => v.toString(),
          from: int.parse,
        );

        await s.removeWhere((v) => v.isEven);
        expect(s.length, 2);
        expect(s.contains(1), true);
        expect(s.contains(3), true);
        expect(s.contains(2), false);
        expect(s.contains(4), false);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('k4')!.toSet(), {'1', '3'});
      },
    );

    test('clear() empties memory and removes key from prefs', () async {
      setMockInitialPreferences({
        'k5': ['foo', 'bar'],
      });
      final s = await _createPersistentSet<String>(
        'k5',
        to: (v) => v,
        from: (s) => s,
      );

      await s.clear();
      expect(s.length, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('k5'), isNull);
    });
  });

  group('Transactional mutations', () {
    test(
      'mutate supports async work, returns a value, and writes once',
      () async {
        final storage = _FakePersistentSetStorage();
        final set = await _createPersistentSet<String>(
          'transaction',
          to: (value) => value,
          from: (value) => value,
          storage: storage,
        );

        final gate = Completer<void>();
        final mutation = set.mutate((draft) async {
          draft.add('first');
          await gate.future;
          draft.add('second');
          return draft.length;
        });

        await Future<void>.delayed(Duration.zero);
        expect(storage.writeCalls, isEmpty);
        expect(set.toSet(), isEmpty);

        gate.complete();
        expect(await mutation, 2);
        expect(set.toSet().toList(), ['first', 'second']);
        expect(storage.writeCalls, [
          ['first', 'second'],
        ]);
      },
    );

    test('mutate skips writes when serialized values do not change', () async {
      final storage = _FakePersistentSetStorage(values: ['value']);
      final set = await _createPersistentSet<String>(
        'unchanged',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );

      final result = await set.mutate((draft) => draft.contains('value'));

      expect(result, isTrue);
      expect(storage.writeCalls, isEmpty);
    });

    test(
      'serialized-equivalent replacements update memory without a write',
      () async {
        final storage = _FakePersistentSetStorage(values: ['1']);
        final set = await _createPersistentSet<Box>(
          'hydration',
          to: (value) => value.id.toString(),
          from: (value) => Box(int.parse(value)),
          storage: storage,
        );
        final replacement = const Box(1);

        await set.mutate((draft) {
          draft
            ..clear()
            ..add(replacement);
        });

        expect(identical(set.lookup(const Box(1)), replacement), isTrue);
        expect(storage.writeCalls, isEmpty);
      },
    );

    test(
      'refresh reuses only unchanged serialized element instances',
      () async {
        final storage = _FakePersistentSetStorage();
        final first = const LabeledBox(1, 'first');
        final second = const LabeledBox(2, 'second');
        var decodeCalls = 0;
        final set = await _createPersistentSet<LabeledBox>(
          'stable-instances',
          to: LabeledBox.encode,
          from: (final encoded) {
            decodeCalls += 1;
            return LabeledBox.decode(encoded);
          },
          seedIfMissing: [first, second],
          storage: storage,
        );

        expect(await set.add(const LabeledBox(1, 'ignored')), isFalse);
        expect(identical(set.lookup(const LabeledBox(1, '')), first), isTrue);
        expect(decodeCalls, 0);

        storage.values = ['2:second', '1:updated', '3:third'];
        await set.reload();

        expect(identical(set.lookup(const LabeledBox(2, '')), second), isTrue);
        final updated = set.lookup(const LabeledBox(1, ''))!;
        expect(identical(updated, first), isFalse);
        expect(updated.label, 'updated');
        expect(set.lookup(const LabeledBox(3, ''))!.label, 'third');
        expect(decodeCalls, 2);
      },
    );

    test('mutate preserves subclass-provided identity semantics', () async {
      final storage = _FakePersistentSetStorage(values: ['1', '1']);
      final first = Box(1);
      final second = Box(1);
      final mem =
          LinkedHashSet<Box>.identity()
            ..add(first)
            ..add(second);
      final set = persistentSetFromMemory<Box>(
        'identity',
        mem,
        storage,
        to: (value) => value.id.toString(),
        from: (value) => Box(int.parse(value)),
      );

      await set.mutate((draft) {
        expect(draft.length, 2);
        expect(draft.add(Box(1)), isTrue);
      });

      expect(set.length, 3);
      expect(storage.values, ['1', '1', '1']);

      final copy = set.toSet();
      expect(copy.add(Box(1)), isTrue);
      expect(copy.length, 4);
      expect(set.length, 3);

      expect((await set.reload()).length, 3);
    });

    test(
      'refresh aligns encoded values with subclass iteration order',
      () async {
        final storage = _FakePersistentSetStorage(values: ['1', '2']);
        final memory = SplayTreeSet<int>((first, second) {
          return second.compareTo(first);
        })..addAll([1, 2]);
        final set = persistentSetFromMemory<int>(
          'sorted',
          memory,
          storage,
          to: (value) => value.toString(),
          from: int.parse,
        );

        storage.values = ['1', '3'];

        expect((await set.reload()).toList(), [3, 1]);
        expect(await set.add(4), isTrue);
        expect(storage.values, ['4', '3', '1']);
      },
    );

    test(
      'serialized snapshots and no-op convenience mutations are cached',
      () async {
        final storage = _FakePersistentSetStorage(values: ['first', 'second']);
        var encodeCalls = 0;
        final set = await _createPersistentSet<String>(
          'encoding',
          to: (value) {
            encodeCalls += 1;
            return value;
          },
          from: (value) => value,
          storage: storage,
        );

        expect(await set.add('first'), isFalse);
        expect(encodeCalls, 0);

        expect(await set.add('third'), isTrue);
        expect(encodeCalls, 3);

        expect(await set.add('fourth'), isTrue);
        expect(encodeCalls, 7);

        expect(await set.remove('missing'), isFalse);
        expect(encodeCalls, 7);
      },
    );

    test('concurrent mutations are committed in invocation order', () async {
      final firstWriteGate = Completer<void>();
      final storage = _FakePersistentSetStorage(writeGates: [firstWriteGate]);
      final set = await _createPersistentSet<String>(
        'serialized',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );

      final first = set.add('first');
      final second = set.add('second');
      await Future<void>.delayed(Duration.zero);

      expect(storage.writeCalls, [
        ['first'],
      ]);
      firstWriteGate.complete();

      expect(await Future.wait([first, second]), [isTrue, isTrue]);
      expect(storage.writeCalls, [
        ['first'],
        ['first', 'second'],
      ]);
      expect(set.toSet().toList(), ['first', 'second']);
    });

    test(
      'instances sharing a storage and key do not overwrite stale snapshots',
      () async {
        final firstWriteGate = Completer<void>();
        final storage = _FakePersistentSetStorage(writeGates: [firstWriteGate]);
        final first = await _createPersistentSet<String>(
          'shared-key',
          to: (value) => value,
          from: (value) => value,
          storage: storage,
        );
        final second = await _createPersistentSet<String>(
          'shared-key',
          to: (value) => value,
          from: (value) => value,
          storage: storage,
        );

        final firstAddition = first.add('first');
        final secondAddition = second.add('second');
        await Future<void>.delayed(Duration.zero);

        expect(storage.writeCalls, [
          ['first'],
        ]);
        firstWriteGate.complete();

        expect(await Future.wait([firstAddition, secondAddition]), [
          isTrue,
          isTrue,
        ]);
        expect(storage.writeCalls, [
          ['first'],
          ['first', 'second'],
        ]);
        expect(storage.values, ['first', 'second']);

        // Instances remain local views until they mutate or explicitly reload.
        expect(first.toSet().toList(), ['first']);
        expect(second.toSet().toList(), ['first', 'second']);
        expect((await first.reload()).toList(), ['first', 'second']);
      },
    );

    test(
      'default storage coordinates distinct async handles for the same key',
      () async {
        final first = await _createPersistentSet<String>(
          'default-shared-key',
          to: (value) => value,
          from: (value) => value,
        );
        final second = await _createPersistentSet<String>(
          'default-shared-key',
          to: (value) => value,
          from: (value) => value,
        );

        expect(await Future.wait([first.add('first'), second.add('second')]), [
          isTrue,
          isTrue,
        ]);

        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        final stored = preferences.getStringList('default-shared-key');
        expect(stored, ['first', 'second']);
        expect((await first.reload()).toList(), ['first', 'second']);
      },
    );

    test(
      'async and legacy adapters coordinate access to the same physical key',
      () async {
        final asyncStorage =
            await SharedPreferencesPersistentSetStorage.create();
        final preferences = await SharedPreferences.getInstance();
        final legacyStorage = SharedPreferencesPersistentSetStorage(
          preferences,
        );
        final asyncEntered = Completer<void>();
        final asyncGate = Completer<void>();

        final asyncTransaction = asyncStorage.transaction<void>(
          'mixed-adapter-key',
          (final transaction) async {
            asyncEntered.complete();
            await asyncGate.future;
          },
        );
        await asyncEntered.future;

        var legacyEntered = false;
        final legacyTransaction = legacyStorage.transaction<void>(
          'mixed-adapter-key',
          (final transaction) {
            legacyEntered = true;
          },
        );
        await Future<void>.delayed(Duration.zero);

        expect(legacyEntered, isFalse);
        asyncGate.complete();
        await Future.wait([asyncTransaction, legacyTransaction]);
        expect(legacyEntered, isTrue);
      },
    );

    test(
      'mixed adapters use a consistent lock order across different keys',
      () async {
        final asyncStorage =
            await SharedPreferencesPersistentSetStorage.create();
        final preferences = await SharedPreferences.getInstance();
        final legacyStorage = SharedPreferencesPersistentSetStorage(
          preferences,
        );
        final asyncEntered = Completer<void>();
        final startNestedLegacyTransaction = Completer<void>();
        final order = <String>[];

        final asyncTransaction = asyncStorage.transaction<void>(
          'lock-order-a',
          (final transaction) async {
            order.add('async-a');
            asyncEntered.complete();
            await startNestedLegacyTransaction.future;
            await legacyStorage.transaction<void>('lock-order-b', (
              final transaction,
            ) {
              order.add('nested-legacy-b');
            });
          },
        );
        await asyncEntered.future;

        final competingLegacyTransaction = legacyStorage.transaction<void>(
          'lock-order-a',
          (final transaction) {
            order.add('competing-legacy-a');
          },
        );
        await Future<void>.delayed(Duration.zero);
        startNestedLegacyTransaction.complete();

        await Future.wait([
          asyncTransaction,
          competingLegacyTransaction,
        ]).timeout(const Duration(seconds: 1));
        expect(order, ['async-a', 'nested-legacy-b', 'competing-legacy-a']);
      },
    );

    test('reload observes writes made outside the storage adapter', () async {
      final set = await _createPersistentSet<String>(
        'external-reload',
        to: (value) => value,
        from: (value) => value,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('external-reload', ['external']);

      expect(set.toSet(), isEmpty);
      expect((await set.reload()).toList(), ['external']);
      expect(set.toSet().toList(), ['external']);
    });

    test(
      'cross-instance reentrant mutation fails instead of deadlocking',
      () async {
        final first = await _createPersistentSet<String>(
          'cross-reentrant',
          to: (value) => value,
          from: (value) => value,
        );
        final second = await _createPersistentSet<String>(
          'cross-reentrant',
          to: (value) => value,
          from: (value) => value,
        );

        await expectLater(
          first
              .mutate<void>((draft) async {
                draft.add('outer');
                await second.add('nested');
              })
              .timeout(const Duration(seconds: 1)),
          throwsA(isA<StateError>()),
        );

        expect(first.toSet(), isEmpty);
        expect(second.toSet(), isEmpty);
        expect(await second.add('later'), isTrue);
        expect(second.toSet().toList(), ['later']);
      },
    );

    test(
      'nested mutations of distinct keys succeed in storage key order',
      () async {
        final first = await _createPersistentSet<String>(
          'nested-first',
          to: (value) => value,
          from: (value) => value,
        );
        final second = await _createPersistentSet<String>(
          'nested-second',
          to: (value) => value,
          from: (value) => value,
        );

        await first.mutate<void>((draft) async {
          draft.add('outer');
          expect(await second.add('inner'), isTrue);
        });

        expect(first.toSet().toList(), ['outer']);
        expect(second.toSet().toList(), ['inner']);
      },
    );

    test(
      'legacy storage rejects nested bundled transactions without deadlocking',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final first = await PersistentSet.create<String>(
          'legacy-nested-first',
          to: (value) => value,
          from: (value) => value,
          preferences: preferences,
        );
        final second = await PersistentSet.create<String>(
          'legacy-nested-second',
          to: (value) => value,
          from: (value) => value,
          preferences: preferences,
        );

        await expectLater(
          first
              .mutate<void>((draft) async {
                draft.add('outer');
                await second.add('inner');
              })
              .timeout(const Duration(seconds: 1)),
          throwsA(isA<StateError>()),
        );

        expect(first.toSet(), isEmpty);
        expect(second.toSet(), isEmpty);
        expect(await second.add('later'), isTrue);
        expect(preferences.getStringList('legacy-nested-first'), isNull);
        expect(preferences.getStringList('legacy-nested-second'), ['later']);
      },
    );

    test(
      'legacy nested rejection prevents a competing-key lock cycle',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final firstStorage = SharedPreferencesPersistentSetStorage(preferences);
        final secondStorage = SharedPreferencesPersistentSetStorage(
          preferences,
        );
        final outerEntered = Completer<void>();
        final tryNested = Completer<void>();
        final order = <String>[];

        final outer = firstStorage.transaction<void>('legacy-cycle-a', (
          final transaction,
        ) async {
          order.add('outer-a');
          outerEntered.complete();
          await tryNested.future;
          expect(
            () => secondStorage.transaction<void>(
              'legacy-cycle-b',
              (final transaction) {},
            ),
            throwsA(isA<StateError>()),
          );
          order.add('nested-rejected');
        });
        await outerEntered.future;

        final competing = secondStorage.transaction<void>('legacy-cycle-b', (
          final transaction,
        ) {
          order.add('competing-b');
        });
        await Future<void>.delayed(Duration.zero);
        tryNested.complete();

        await Future.wait([
          outer,
          competing,
        ]).timeout(const Duration(seconds: 1));
        expect(order, ['outer-a', 'nested-rejected', 'competing-b']);
      },
    );

    test('mixed add and remove operations retain invocation order', () async {
      final storage = _FakePersistentSetStorage(values: ['value']);
      final set = await _createPersistentSet<String>(
        'mixed',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );

      final removal = set.remove('value');
      final addition = set.add('value');

      expect(await removal, isTrue);
      expect(await addition, isTrue);
      expect(storage.writeCalls, [
        <String>[],
        ['value'],
      ]);
      expect(set.toSet().toList(), ['value']);
    });

    test(
      'a false write result rolls back and does not poison the queue',
      () async {
        final storage = _FakePersistentSetStorage()..writeResult = false;
        final set = await _createPersistentSet<String>(
          'false-write',
          to: (value) => value,
          from: (value) => value,
          storage: storage,
        );

        await expectLater(
          set.add('lost'),
          throwsA(isA<PersistentSetPersistenceException>()),
        );
        expect(set.toSet(), isEmpty);
        expect(storage.values, isNull);

        storage.writeResult = true;
        expect(await set.add('saved'), isTrue);
        expect(set.toSet().toList(), ['saved']);
        expect(storage.values, ['saved']);
      },
    );

    test('a thrown write and callback failure both roll back', () async {
      final storage = _FakePersistentSetStorage(values: ['original']);
      final set = await _createPersistentSet<String>(
        'throwing',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );

      storage.throwOnWrite = true;
      await expectLater(set.add('write-failure'), throwsStateError);
      expect(set.toSet().toList(), ['original']);
      expect(storage.values, ['original']);

      storage.throwOnWrite = false;
      await expectLater(
        set.mutate<void>((draft) {
          draft.add('callback-failure');
          throw StateError('callback failed');
        }),
        throwsStateError,
      );
      expect(set.toSet().toList(), ['original']);
      expect(storage.values, ['original']);
    });

    test('clear rolls back when key removal fails', () async {
      final storage = _FakePersistentSetStorage(values: ['original'])
        ..removeResult = false;
      final set = await _createPersistentSet<String>(
        'clear-failure',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );

      await expectLater(
        set.clear(),
        throwsA(isA<PersistentSetPersistenceException>()),
      );

      expect(set.toSet().toList(), ['original']);
      expect(storage.values, ['original']);
    });

    test(
      'SharedPreferences storage restores its cache after false results',
      () async {
        final store =
            _ControllableSharedPreferencesStore({
                'flutter.cache': <String>['original'],
              })
              ..writeResult = false
              ..removeResult = false;
        SharedPreferencesStorePlatform.instance = store;
        final preferences = await SharedPreferences.getInstance();
        final storage = SharedPreferencesPersistentSetStorage(preferences);

        expect(
          await storage.transaction(
            'cache',
            (final transaction) => transaction.write(['changed']),
          ),
          isFalse,
        );
        expect(preferences.getStringList('cache'), ['original']);

        expect(
          await storage.transaction(
            'cache',
            (final transaction) => transaction.remove(),
          ),
          isFalse,
        );
        expect(preferences.getStringList('cache'), ['original']);
      },
    );

    test(
      'SharedPreferences storage restores its cache after thrown failures',
      () async {
        final store =
            _ControllableSharedPreferencesStore({
                'flutter.cache': <String>['original'],
              })
              ..throwOnWrite = true
              ..throwOnRemove = true;
        SharedPreferencesStorePlatform.instance = store;
        final preferences = await SharedPreferences.getInstance();
        final storage = SharedPreferencesPersistentSetStorage(preferences);

        await expectLater(
          storage.transaction(
            'cache',
            (final transaction) => transaction.write(['changed']),
          ),
          throwsStateError,
        );
        expect(preferences.getStringList('cache'), ['original']);

        await expectLater(
          storage.transaction(
            'cache',
            (final transaction) => transaction.remove(),
          ),
          throwsStateError,
        );
        expect(preferences.getStringList('cache'), ['original']);
      },
    );

    test(
      'default storage does not expose optimistic values through legacy cache',
      () async {
        setMockInitialPreferences({
          'cache': <String>['original'],
        });
        final legacyPreferences = await SharedPreferences.getInstance();
        final asyncStore = _GatedFailingAsyncPreferences({
          'flutter.cache': <String>['original'],
        });
        SharedPreferencesAsyncPlatform.instance = asyncStore;
        final storage = await SharedPreferencesPersistentSetStorage.create();

        final write = storage.transaction(
          'cache',
          (final transaction) => transaction.write(['changed']),
        );
        await asyncStore.writeStarted.future;

        expect(legacyPreferences.getStringList('cache'), ['original']);
        asyncStore.writeGate.complete();
        await expectLater(write, throwsStateError);
        expect(legacyPreferences.getStringList('cache'), ['original']);
        expect(storage.read('cache'), ['original']);
      },
    );

    test('default storage retains the legacy Android namespace', () async {
      final asyncStore = _RecordingAsyncPreferences({
        'flutter.legacy-key': <String>['stored'],
      });
      SharedPreferencesAsyncPlatform.instance = asyncStore;
      final storage = await SharedPreferencesPersistentSetStorage.create();

      final set = await _createPersistentSet<String>(
        'legacy-key',
        to: (value) => value,
        from: (value) => value,
        storage: storage,
      );

      expect(set.toSet(), {'stored'});
      expect(asyncStore.lastReadKey, 'flutter.legacy-key');
      final options = asyncStore.lastOptions;
      expect(options, isA<SharedPreferencesAsyncAndroidOptions>());
      final androidOptions = options! as SharedPreferencesAsyncAndroidOptions;
      expect(
        androidOptions.backend,
        SharedPreferencesAndroidBackendLibrary.SharedPreferences,
      );
      expect(
        androidOptions.originalSharedPreferencesOptions?.fileName,
        'FlutterSharedPreferences',
      );
    });

    test(
      'SharedPreferences cache rollback waits for writes from other adapters',
      () async {
        final store = _RacingSharedPreferencesStore();
        SharedPreferencesStorePlatform.instance = store;
        final preferences = await SharedPreferences.getInstance();
        final firstStorage = SharedPreferencesPersistentSetStorage(preferences);
        final secondStorage = SharedPreferencesPersistentSetStorage(
          preferences,
        );

        final successfulWrite = firstStorage.transaction(
          'first',
          (final transaction) => transaction.write(['changed']),
        );
        await store.firstWriteStarted.future;

        final failedWrite = secondStorage.transaction(
          'second',
          (final transaction) => transaction.write(['changed']),
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.secondWriteStarted, isFalse);

        store.firstWriteGate.complete();
        expect(await successfulWrite, isTrue);
        expect(await failedWrite, isFalse);

        expect(preferences.getStringList('first'), ['changed']);
        expect(preferences.getStringList('second'), ['original']);
      },
    );

    test(
      'reentrant mutation fails fast and does not poison the queue',
      () async {
        final storage = _FakePersistentSetStorage(values: ['original']);
        final set = await _createPersistentSet<String>(
          'reentrant',
          to: (value) => value,
          from: (value) => value,
          storage: storage,
        );

        await expectLater(
          set
              .mutate<void>((draft) async {
                draft.add('outer');
                await set.add('nested');
              })
              .timeout(const Duration(seconds: 1)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('mutate its provided draft instead'),
            ),
          ),
        );

        expect(set.toSet().toList(), ['original']);
        expect(storage.values, ['original']);
        expect(await set.add('later'), isTrue);
        expect(set.toSet().toList(), ['original', 'later']);
      },
    );

    test('cross-key mutation cycles reject the descending branch', () async {
      final first = await _createPersistentSet<String>(
        'cycle-first',
        to: (value) => value,
        from: (value) => value,
      );
      final second = await _createPersistentSet<String>(
        'cycle-second',
        to: (value) => value,
        from: (value) => value,
      );
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();

      final firstMutation = first.mutate<void>((draft) async {
        draft.add('first');
        firstEntered.complete();
        await secondEntered.future;
        await second.add('from-first');
      });
      final secondMutation = second.mutate<void>((draft) async {
        draft.add('second');
        secondEntered.complete();
        await firstEntered.future;
        await first.add('from-second');
      });

      await expectLater(
        Future.wait([
          firstMutation,
          secondMutation,
        ]).timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
      expect(first.toSet().toList(), ['first']);
      expect(second.toSet().toList(), ['from-first']);
      expect(await first.add('later-first'), isTrue);
      expect(await second.add('later-second'), isTrue);
    });
  });

  group('Read-only behaviors', () {
    test('contains() and length reflect memory', () async {
      setMockInitialPreferences({
        'k6': ['x', 'y'],
      });
      final s = await _createPersistentSet<String>(
        'k6',
        to: (v) => v,
        from: (s) => s,
      );
      expect(s.length, 2);
      expect(s.contains('x'), true);
      expect(s.contains('nope'), false);
    });

    test('lookup() returns the stored instance when T overrides ==', () async {
      final boxes = [const Box(1), const Box(2)];
      final s = await _createPersistentSet<Box>(
        'k7',
        to: (b) => b.id.toString(),
        from: (s) => Box(int.parse(s)),
        seedIfMissing: boxes,
      );

      // New instance equal to an existing one.
      final query = const Box(2);
      final found = s.lookup(query);

      // Should be the identical instance that was stored (not just ==).
      expect(identical(found, boxes[1]), true);
      expect(found, boxes[1]); // also ==
    });

    test('toSet() returns a defensive copy', () async {
      setMockInitialPreferences({
        'k8': ['r', 's'],
      });
      final s = await _createPersistentSet<String>(
        'k8',
        to: (v) => v,
        from: (s) => s,
      );

      final copy = s.toSet();
      expect(copy, {'r', 's'});

      // Mutating the returned Set must not affect PersistentSet or prefs.
      copy.add('t');
      expect(copy.length, 3);
      expect(s.length, 2); // unchanged

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('k8')!.toSet(), {'r', 's'});
    });
  });

  group('Complex object (Person)', () {
    test('create() loads existing JSON and respects custom equality', () async {
      final p1 = Person(
        id: 'u1',
        name: 'Ada',
        age: 28,
        tags: {'admin', 'active'},
        createdAt: DateTime.utc(2024, 5, 1),
      );
      final p2 = Person(
        id: 'u2',
        name: 'Linus',
        age: 33,
        tags: {'active'},
        createdAt: DateTime.utc(2024, 6, 2),
      );

      setMockInitialPreferences({
        'people': [Person.encode(p1), Person.encode(p2)],
      });

      final s = await _createPersistentSet<Person>(
        'people',
        to: Person.encode,
        from: Person.decode,
      );

      expect(s.length, 2);

      // contains() should use == (id only), not object identity.
      final probe = Person(
        id: 'u1',
        name: 'Different Name',
        age: 99,
        tags: {'zzz'},
        createdAt: DateTime.utc(1999, 1, 1),
      );
      expect(s.contains(probe), true);
    });

    test(
      'lookup() returns the stored instance, not just an equal one',
      () async {
        final seed = <Person>{
          Person(
            id: 'a',
            name: 'Alice',
            age: 30,
            tags: {'active'},
            createdAt: DateTime.utc(2024, 1, 10),
          ),
          Person(
            id: 'b',
            name: 'Bob',
            age: 41,
            tags: {'inactive'},
            createdAt: DateTime.utc(2024, 2, 11),
          ),
        };

        final s = await _createPersistentSet<Person>(
          'people_seed',
          to: Person.encode,
          from: Person.decode,
          seedIfMissing: seed,
        );

        // Equal-by-id instance should yield the identical stored instance.
        final query = Person(
          id: 'b',
          name: 'Different',
          age: 1,
          tags: {},
          createdAt: DateTime.utc(2000, 1, 1),
        );
        final found = s.lookup(query);
        final seededBob = seed.firstWhere((p) => p.id == 'b');

        expect(identical(found, seededBob), true);
        expect(found, seededBob); // also ==
      },
    );

    test(
      'addAll() + removeWhere() persist correctly with complex predicates',
      () async {
        final s = await _createPersistentSet<Person>(
          'people_mut',
          to: Person.encode,
          from: Person.decode,
        );

        final ada = Person(
          id: 'ada',
          name: 'Ada',
          age: 28,
          tags: {'admin', 'active'},
          createdAt: DateTime.utc(2024, 5, 1),
        );
        final linus = Person(
          id: 'linus',
          name: 'Linus',
          age: 33,
          tags: {'active'},
          createdAt: DateTime.utc(2024, 6, 2),
        );
        final grace = Person(
          id: 'grace',
          name: 'Grace',
          age: 52,
          tags: {'inactive', 'vip'},
          createdAt: DateTime.utc(2023, 12, 31),
        );

        await s.addAll([ada, linus]);
        var prefs = await SharedPreferences.getInstance();
        // Compare by ids after decoding persisted JSON.
        final savedIds1 =
            prefs
                .getStringList('people_mut')!
                .map(Person.decode)
                .map((p) => p.id)
                .toSet();
        expect(savedIds1, {'ada', 'linus'});

        // Adding an existing person should not persist again (size unchanged).
        await s.addAll([ada]);
        prefs = await SharedPreferences.getInstance();
        final savedIds2 =
            prefs
                .getStringList('people_mut')!
                .map(Person.decode)
                .map((p) => p.id)
                .toSet();
        expect(savedIds2, {'ada', 'linus'});

        // Adding a new one persists again.
        await s.addAll([grace]);
        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final savedIds3 =
            prefs
                .getStringList('people_mut')!
                .map(Person.decode)
                .map((p) => p.id)
                .toSet();
        expect(savedIds3, {'ada', 'linus', 'grace'});

        // Remove everyone who is age >= 50 OR tagged 'inactive'.
        await s.removeWhere((p) => p.age >= 50 || p.tags.contains('inactive'));
        expect(s.contains(grace), false);
        expect(s.contains(linus), true);
        expect(s.contains(ada), true);

        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final savedIds4 =
            prefs
                .getStringList('people_mut')!
                .map(Person.decode)
                .map((p) => p.id)
                .toSet();
        expect(savedIds4, {'ada', 'linus'});
      },
    );

    test('clear() removes the key for complex object sets', () async {
      final s = await _createPersistentSet<Person>(
        'people_clear',
        to: Person.encode,
        from: Person.decode,
        seedIfMissing: {
          Person(
            id: 'x',
            name: 'X',
            age: 1,
            tags: {},
            createdAt: DateTime.utc(2024, 1, 1),
          ),
        },
      );

      await s.clear();
      expect(s.length, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('people_clear'), isNull);
    });
  });
}

final class _PersistentSetSubclass extends PersistentSet<String> {
  _PersistentSetSubclass(
    final String key,
    final Set<String> values,
    final SharedPreferences preferences,
    final String Function(String value) encode,
  ) : super.internal(key, values, preferences, encode, (value) => value);
}

final class _FakePersistentSetStorage implements PersistentSetStorage {
  List<String>? values;
  final List<List<String>> writeCalls = [];
  final List<Completer<void>> writeGates;
  var _transactionTail = Future<void>.value();
  var writeResult = true;
  var removeResult = true;
  var throwOnWrite = false;

  _FakePersistentSetStorage({
    final List<String>? values,
    this.writeGates = const [],
  }) : values = values == null ? null : List<String>.of(values);

  @override
  List<String>? read(final String key) {
    final current = values;
    return current == null ? null : List<String>.of(current);
  }

  @override
  Future<R> transaction<R>(
    final String key,
    final FutureOr<R> Function(PersistentSetStorageTransaction transaction)
    action,
  ) {
    final result = _transactionTail.then<R>((final _) async {
      return action(_FakePersistentSetStorageTransaction(this));
    });
    _transactionTail = result.then<void>(
      (final _) {},
      onError: (final Object _, final StackTrace _) {},
    );
    return result;
  }

  Future<bool> _remove() async {
    if (removeResult) {
      values = null;
    }
    return removeResult;
  }

  Future<bool> _write(final List<String> values) async {
    final callIndex = writeCalls.length;
    writeCalls.add(List<String>.of(values));
    if (callIndex < writeGates.length) {
      await writeGates[callIndex].future;
    }
    if (throwOnWrite) {
      throw StateError('write failed');
    }
    if (writeResult) {
      this.values = List<String>.of(values);
    }
    return writeResult;
  }
}

final class _FakePersistentSetStorageTransaction
    implements PersistentSetStorageTransaction {
  final _FakePersistentSetStorage _storage;

  _FakePersistentSetStorageTransaction(this._storage);

  @override
  List<String>? read() => _storage.read('');

  @override
  Future<bool> remove() => _storage._remove();

  @override
  Future<bool> write(final List<String> values) => _storage._write(values);
}

final class _ControllableSharedPreferencesStore
    extends SharedPreferencesStorePlatform {
  final InMemorySharedPreferencesStore _backend;
  var writeResult = true;
  var removeResult = true;
  var throwOnWrite = false;
  var throwOnRemove = false;

  _ControllableSharedPreferencesStore(final Map<String, Object> values)
    : _backend = InMemorySharedPreferencesStore.withData(values);

  @override
  Future<bool> clear() => _backend.clear();

  @override
  Future<Map<String, Object>> getAll() => _backend.getAll();

  @override
  Future<bool> remove(final String key) {
    if (throwOnRemove) {
      throw StateError('remove failed');
    }
    return removeResult ? _backend.remove(key) : Future<bool>.value(false);
  }

  @override
  Future<bool> setValue(
    final String valueType,
    final String key,
    final Object value,
  ) {
    if (throwOnWrite) {
      throw StateError('write failed');
    }
    return writeResult
        ? _backend.setValue(valueType, key, value)
        : Future<bool>.value(false);
  }
}

final class _RacingSharedPreferencesStore
    extends SharedPreferencesStorePlatform {
  final _backend = InMemorySharedPreferencesStore.withData({
    'flutter.first': <String>['original'],
    'flutter.second': <String>['original'],
  });
  final firstWriteStarted = Completer<void>();
  final firstWriteGate = Completer<void>();
  var secondWriteStarted = false;

  @override
  Future<bool> clear() => _backend.clear();

  @override
  Future<Map<String, Object>> getAll() => _backend.getAll();

  @override
  Future<bool> remove(final String key) => _backend.remove(key);

  @override
  Future<bool> setValue(
    final String valueType,
    final String key,
    final Object value,
  ) async {
    if (key == 'flutter.first') {
      firstWriteStarted.complete();
      await firstWriteGate.future;
      return _backend.setValue(valueType, key, value);
    }

    secondWriteStarted = true;
    return false;
  }
}

final class _GatedFailingAsyncPreferences
    extends InMemorySharedPreferencesAsync {
  final writeStarted = Completer<void>();
  final writeGate = Completer<void>();

  _GatedFailingAsyncPreferences(super.data) : super.withData();

  @override
  Future<bool> setStringList(
    final String key,
    final List<String> value,
    final SharedPreferencesOptions options,
  ) async {
    writeStarted.complete();
    await writeGate.future;
    throw StateError('write failed');
  }
}

final class _RecordingAsyncPreferences extends InMemorySharedPreferencesAsync {
  String? lastReadKey;
  SharedPreferencesOptions? lastOptions;

  _RecordingAsyncPreferences(super.data) : super.withData();

  @override
  Future<List<String>?> getStringList(
    final String key,
    final SharedPreferencesOptions options,
  ) {
    lastReadKey = key;
    lastOptions = options;
    return super.getStringList(key, options);
  }
}

// Simple value class to validate Set.lookup preserves the stored instance.
class Box {
  final int id;
  const Box(this.id);
  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) => other is Box && other.id == id;
  @override
  String toString() => 'Box($id)';
}

class LabeledBox {
  final int id;
  final String label;

  const LabeledBox(this.id, this.label);

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(final Object other) {
    return other is LabeledBox && other.id == id;
  }

  static String encode(final LabeledBox box) => '${box.id}:${box.label}';

  static LabeledBox decode(final String encoded) {
    final separator = encoded.indexOf(':');
    return LabeledBox(
      int.parse(encoded.substring(0, separator)),
      encoded.substring(separator + 1),
    );
  }
}

// More complex value with multiple fields and JSON (de)serialization.
class Person {
  final String id; // equality by id only
  final String name;
  final int age;
  final Set<String> tags;
  final DateTime createdAt;

  const Person({
    required this.id,
    required this.name,
    required this.age,
    required this.tags,
    required this.createdAt,
  });

  @override
  int get hashCode => id.hashCode;

  // Equality by id makes lookup() meaningful even if other fields differ.
  @override
  bool operator ==(Object other) => other is Person && other.id == id;

  @override
  String toString() =>
      'Person(id=$id, name=$name, age=$age, tags=$tags, createdAt=$createdAt)';

  static Person decode(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return Person(
      id: m['id'] as String,
      name: m['name'] as String,
      age: m['age'] as int,
      tags: Set<String>.from(m['tags'] as List),
      createdAt: DateTime.parse(m['createdAt'] as String),
    );
  }

  static String encode(Person p) => jsonEncode({
    'id': p.id,
    'name': p.name,
    'age': p.age,
    'tags': p.tags.toList(),
    'createdAt': p.createdAt.toIso8601String(),
  });
}
