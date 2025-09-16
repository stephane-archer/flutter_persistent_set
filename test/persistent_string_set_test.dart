import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:persistent_string_set/persistent_string_set.dart';

void main() {
  const testKey = 'test_set';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
