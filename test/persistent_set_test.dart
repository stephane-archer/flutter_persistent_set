import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:persistent_set/persistent_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Reset prefs before each test.
    SharedPreferences.setMockInitialValues({});
  });

  group('PersistentSet.create', () {
    test('loads existing values', () async {
      SharedPreferences.setMockInitialValues({
        'ints': ['1', '2', '3'],
      });

      final s = await PersistentSet.create<int>(
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
      final s = await PersistentSet.create<String>(
        'strings',
        to: (v) => v,
        from: (s) => s,
      );
      expect(s.length, 0);
    });

    test('seeds when empty and persists immediately', () async {
      final seed = <String>{'a', 'b'};
      final s = await PersistentSet.create<String>(
        'seeded',
        to: (v) => v,
        from: (s) => s,
        seedIfEmpty: seed,
      );
      expect(s.length, seed.length);
      expect(s.contains('a'), true);
      expect(s.contains('b'), true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('seeded')!.toSet(), seed);
    });
  });

  group('Mutations persist correctly', () {
    test('add() adds and persists; duplicate add() returns false', () async {
      final s = await PersistentSet.create<int>(
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
      final s = await PersistentSet.create<String>(
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
      expect(prefs.getStringList('k2')!.toSet(), {'x', 'y', 'z'});
    });

    test(
      'remove() removes existing value and persists, returns false if missing',
      () async {
        SharedPreferences.setMockInitialValues({
          'k3': ['1', '2'],
        });
        final s = await PersistentSet.create<int>(
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
        SharedPreferences.setMockInitialValues({
          'k4': ['1', '2', '3', '4'],
        });
        final s = await PersistentSet.create<int>(
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
      SharedPreferences.setMockInitialValues({
        'k5': ['foo', 'bar'],
      });
      final s = await PersistentSet.create<String>(
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

  group('Read-only behaviors', () {
    test('contains() and length reflect memory', () async {
      SharedPreferences.setMockInitialValues({
        'k6': ['x', 'y'],
      });
      final s = await PersistentSet.create<String>(
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
      final s = await PersistentSet.create<Box>(
        'k7',
        to: (b) => b.id.toString(),
        from: (s) => Box(int.parse(s)),
        seedIfEmpty: boxes,
      );

      // New instance equal to an existing one.
      final query = const Box(2);
      final found = s.lookup(query);

      // Should be the identical instance that was stored (not just ==).
      expect(identical(found, boxes[1]), true);
      expect(found, boxes[1]); // also ==
    });

    test('toSet() returns a defensive copy', () async {
      SharedPreferences.setMockInitialValues({
        'k8': ['r', 's'],
      });
      final s = await PersistentSet.create<String>(
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

      SharedPreferences.setMockInitialValues({
        'people': [Person.encode(p1), Person.encode(p2)],
      });

      final s = await PersistentSet.create<Person>(
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

        final s = await PersistentSet.create<Person>(
          'people_seed',
          to: Person.encode,
          from: Person.decode,
          seedIfEmpty: seed,
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
        final s = await PersistentSet.create<Person>(
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
        final savedIds1 = prefs
            .getStringList('people_mut')!
            .map(Person.decode)
            .map((p) => p.id)
            .toSet();
        expect(savedIds1, {'ada', 'linus'});

        // Adding an existing person should not persist again (size unchanged).
        await s.addAll([ada]);
        prefs = await SharedPreferences.getInstance();
        final savedIds2 = prefs
            .getStringList('people_mut')!
            .map(Person.decode)
            .map((p) => p.id)
            .toSet();
        expect(savedIds2, {'ada', 'linus'});

        // Adding a new one persists again.
        await s.addAll([grace]);
        prefs = await SharedPreferences.getInstance();
        final savedIds3 = prefs
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
        final savedIds4 = prefs
            .getStringList('people_mut')!
            .map(Person.decode)
            .map((p) => p.id)
            .toSet();
        expect(savedIds4, {'ada', 'linus'});
      },
    );

    test('clear() removes the key for complex object sets', () async {
      final s = await PersistentSet.create<Person>(
        'people_clear',
        to: Person.encode,
        from: Person.decode,
        seedIfEmpty: {
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
