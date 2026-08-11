import 'package:flutter_test/flutter_test.dart';
import 'package:persistent_set/persistent_set.dart';
import 'package:persistent_set/persistent_set_storage.dart';
import 'package:persistent_set/src/persistent_set_storage.dart'
    show SharedPreferencesPersistentSetStorage;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_preferences.dart';

void main() {
  const testKey = 'test_set';

  setUp(() {
    setMockInitialPreferences({});
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  test('create returns an empty set', () async {
    final set = await PersistentStringSet.create(testKey);
    expect(set.length, 0);
    expect(set.toSet(), <String>{});
  });

  test('create supports the standard SharedPreferences test mock', () async {
    SharedPreferences.setMockInitialValues({
      testKey: <String>['mocked'],
    });
    final preferences = await SharedPreferences.getInstance();

    final set = await PersistentStringSet.create(
      testKey,
      preferences: preferences,
    );

    expect(set.toSet(), {'mocked'});
    await set.add('written');
    expect(preferences.getStringList(testKey), ['mocked', 'written']);
  });

  test('create accepts an injected storage backend', () async {
    final preferences = await SharedPreferences.getInstance();
    final PersistentSetStorage storage = SharedPreferencesPersistentSetStorage(
      preferences,
    );

    final set = await PersistentStringSet.create(testKey, storage: storage);
    await set.add('stored');

    expect(preferences.getStringList(testKey), ['stored']);
  });

  test('rejects custom storage with legacy preferences', () async {
    final preferences = await SharedPreferences.getInstance();
    final storage = SharedPreferencesPersistentSetStorage(preferences);

    expect(
      () => PersistentStringSet.create(
        testKey,
        storage: storage,
        preferences: preferences,
      ),
      throwsArgumentError,
    );
  });

  test('create seeds when its storage key does not exist', () async {
    final set = await PersistentStringSet.create(
      testKey,
      seedIfMissing: {'default'},
    );

    expect(set.toSet(), {'default'});
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(testKey), ['default']);
  });

  test('create does not seed an existing empty stored set', () async {
    setMockInitialPreferences({testKey: <String>[]});

    final set = await PersistentStringSet.create(
      testKey,
      seedIfMissing: {'default'},
    );

    expect(set.toSet(), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(testKey), isEmpty);
  });

  test('create persists an empty seed for a missing storage key', () async {
    final set = await PersistentStringSet.create(
      testKey,
      seedIfMissing: <String>{},
    );

    expect(set.toSet(), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(testKey), isTrue);
    expect(preferences.getStringList(testKey), isEmpty);

    final recreated = await PersistentStringSet.create(
      testKey,
      seedIfMissing: {'default'},
    );
    expect(recreated.toSet(), isEmpty);
  });

  test('deprecated seedIfEmpty retains existing-empty behavior', () async {
    setMockInitialPreferences({testKey: <String>[]});

    final set = await PersistentStringSet.create(
      testKey,
      // ignore: deprecated_member_use_from_same_package
      seedIfEmpty: {'legacy-default'},
    );

    expect(set.toSet(), {'legacy-default'});
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(testKey), ['legacy-default']);
  });

  test('deprecated empty seed does not create a missing key', () async {
    final set = await PersistentStringSet.create(
      testKey,
      // ignore: deprecated_member_use_from_same_package
      seedIfEmpty: <String>{},
    );

    expect(set.toSet(), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(testKey), isFalse);
  });

  test('rejects both seed parameter names', () async {
    expect(
      () => PersistentStringSet.create(
        testKey,
        seedIfMissing: {'new'},
        // ignore: deprecated_member_use_from_same_package
        seedIfEmpty: {'legacy'},
      ),
      throwsArgumentError,
    );
  });

  test('add, contains, length, and toSet work correctly', () async {
    final set = await PersistentStringSet.create(testKey);

    // Add a new element
    expect(await set.add('a'), isTrue);
    expect(set.length, 1);
    expect(set.contains('a'), isTrue);
    expect(set.toSet(), {'a'});

    // Add another element
    expect(await set.add('b'), isTrue);
    expect(set.length, 2);
    expect(set.contains('b'), isTrue);
    expect(set.toSet(), {'a', 'b'});

    // Try to add an existing element
    expect(await set.add('a'), isFalse);
    expect(set.length, 2);
  });

  test('remove works correctly', () async {
    final set = await PersistentStringSet.create(testKey);
    await set.add('a');
    await set.add('b');

    // Remove an existing element
    expect(await set.remove('a'), isTrue);
    expect(set.length, 1);
    expect(set.contains('a'), isFalse);
    expect(set.toSet(), {'b'});

    // Try to remove a non-existent element
    expect(await set.remove('c'), isFalse);
    expect(set.length, 1);
  });

  test('removeWhere works correctly', () async {
    final set = await PersistentStringSet.create(testKey);
    await set.add('a');
    await set.add('b');
    await set.add('c');

    // Remove elements that match the condition
    await set.removeWhere((s) => s == 'a' || s == 'c');
    expect(set.length, 1);
    expect(set.contains('a'), isFalse);
    expect(set.contains('c'), isFalse);
    expect(set.contains('b'), isTrue);
    expect(set.toSet(), {'b'});
  });

  test('clear removes all elements', () async {
    final set = await PersistentStringSet.create(testKey);
    await set.add('a');
    await set.add('b');

    expect(set.length, 2);

    await set.clear();
    expect(set.length, 0);
    expect(set.contains('a'), isFalse);
    expect(set.toSet(), <String>{});
  });

  test('lookup returns the element if it exists', () async {
    final set = await PersistentStringSet.create(testKey);
    await set.add('a');

    expect(set.lookup('a'), 'a');
    expect(set.lookup('b'), isNull);
  });

  test('data persists between instances', () async {
    // Create a set and add some data
    final set1 = await PersistentStringSet.create(testKey);
    await set1.add('a');
    await set1.add('b');

    // Create a new instance with the same key
    final set2 = await PersistentStringSet.create(testKey);
    expect(set2.length, 2);
    expect(set2.contains('a'), isTrue);
    expect(set2.contains('b'), isTrue);
    expect(set2.toSet(), {'a', 'b'});

    // Modify the set with the second instance
    await set2.remove('a');
    await set2.add('c');

    // Create a third instance to check if changes persisted
    final set3 = await PersistentStringSet.create(testKey);
    expect(set3.length, 2);
    expect(set3.contains('a'), isFalse);
    expect(set3.contains('b'), isTrue);
    expect(set3.contains('c'), isTrue);
    expect(set3.toSet(), {'b', 'c'});
  });
}
