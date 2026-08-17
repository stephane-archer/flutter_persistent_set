# Persistent Set

A persistent `Set<T>`-like collection for Flutter.

## Features

- Preserves insertion order and set uniqueness.
- Persists mutations automatically.
- Serializes mutations by storage and key, including across instances.
- Refreshes persisted membership before every mutation to prevent stale writes.
- Commits membership changes only after the storage operation completes
  successfully.
- Retains existing element instances when their serialized values are unchanged.
- Supports asynchronous membership transactions.

## Getting started

Persistent Set requires Flutter 3.29.0 or newer.

Add the package to `pubspec.yaml`:

```yaml
dependencies:
  persistent_set: ^1.0.1
```

## Usage

Create a string set with `PersistentStringSet`:

```dart
import 'package:persistent_set/persistent_set.dart';

final favorites = await PersistentStringSet.create('user_favorites');

await favorites.add('item_123');
final isFavorite = favorites.contains('item_123');
final savedFavorites = favorites.toSet();
```

For another type, provide synchronous string codecs:

```dart
import 'package:persistent_set/persistent_set.dart';

final visitedPages = await PersistentSet.create<int>(
  'visited_pages',
  to: (value) => value.toString(),
  from: int.parse,
);

await visitedPages.add(42);
```

Treat the codecs as part of the persisted data schema. They must be
deterministic and preserve set equality: `from(to(value))` must compare equal
to `value` and produce a compatible `hashCode`. Distinct values that may coexist
in the set must encode to distinct strings. Keep existing encodings readable
across app versions, or migrate stored values when changing a codec.

Use `mutate` when several changes or asynchronous work must be committed as
one ordered operation:

```dart
final item = await loadFavoriteId();
final added = await favorites.mutate((draft) => draft.add(item));
```

Mutations using the same storage coordinator and key are serialized, including
mutations from different `PersistentSet` instances. Every mutation refreshes
the latest persisted membership before creating its draft, so a stale instance
cannot overwrite values committed by an earlier operation. When operations
conflict, transaction order determines the final set.

The storage-key lock remains held until an asynchronous `mutate` callback and
its storage operation complete. Keep callbacks short and resolve independent
data before calling `mutate` when practical. Re-entering the same storage key
before the callback completes throws a `StateError`. The default async storage
permits nested mutations of distinct keys when those keys are acquired in
lexicographically ascending order, giving every nested operation a consistent
lock order and preventing dependency cycles. The injected legacy
`SharedPreferences` adapter rejects nested bundled-storage transactions because
it must serialize reloads of the API's whole cache. Apply membership changes
for the current set to the provided draft.

Sets created through `PersistentSet.create` and `PersistentStringSet.create`
receive an insertion-ordered draft with independent membership. During the
storage refresh, elements whose encoded values are unchanged reuse their
existing in-memory instances; new or changed encoded values are decoded. If the
callback or storage write fails, membership and iteration order remain
unchanged. Subclasses that supply another standard Dart `Set` implementation
retain that set's equality and iteration semantics in the draft.

Always await a mutating method before reading the updated membership. Changes
become visible through the instance only after the storage operation completes
successfully.

Every mutation performs a storage read before an optional write. Prefer one
`mutate` call over several convenience mutations when applying a batch. The
legacy `SharedPreferences` adapter also reloads the complete preferences cache
before each transaction; the default async adapter performs a direct key read.

Instances are local views and are not updated when another instance commits.
Call `reload` for an authoritative read that also updates the instance:

```dart
final latestFavorites = await favorites.reload();
```

The older `toSet(reload: true)` option is deprecated. It can only return the
latest value already observed by that storage handle because its
return type is synchronous.

The draft is shallow and contains the same element instances as the current
set. Treat elements as immutable and change only the draft's membership; object
mutations cannot be rolled back. Do not retain the draft. Calling another
mutating method for the same storage key from inside the callback throws a
`StateError`; mutate the provided draft instead.

## Custom storage

Implement `PersistentSetStorage` and `PersistentSetStorageTransaction` when a
set needs another backend or deterministic storage failures in tests, then pass
it to either public factory:

```dart
import 'package:persistent_set/persistent_set.dart';
import 'package:persistent_set/persistent_set_storage.dart';

final favorites = await PersistentStringSet.create(
  'user_favorites',
  storage: storage,
);
```

The storage contracts use a separate, advanced entry point so they do not
clutter the default package API. Most applications need only
`package:persistent_set/persistent_set.dart`.

A storage implementation must serialize transactions that target the same
logical backend and key, including transactions from different storage
handles, and load the latest value before invoking each callback. It must invoke
the callback exactly once and hold the lock until its synchronous or
asynchronous result completes, including when it fails. Values returned by
either read method must be detached snapshots, and implementations that retain
values passed to `write` must snapshot them before its future completes. Custom
storage owns its key namespace, so `keyPrefix` applies only to the bundled
SharedPreferences adapters. Do not provide both `storage` and `preferences`.

The outer storage contract exposes only a synchronous last-observed `read` and
`transaction`. Authoritative reads, writes, and removals happen through the
transaction handle. This prevents callers from bypassing serialization and
keeps custom backends focused on the operations used by `PersistentSet`.

## Persistence

The package uses `SharedPreferencesAsync`, so failed or in-flight writes never
appear in the legacy global `SharedPreferences` cache. On Android it explicitly
selects the legacy SharedPreferences backend, and on every platform it retains
the `flutter.` key prefix, so data written by package version 0.1 remains
available. If the legacy API was configured with another prefix, pass the same
prefix when creating the set:

```dart
final favorites = await PersistentStringSet.create(
  'user_favorites',
  keyPrefix: 'custom.',
);
```

Because the default adapter deliberately does not mutate the legacy singleton's
cache, code that reads these keys through `SharedPreferences.getInstance()` may
remain stale. Calling `reload()` refreshes that cache on platforms whose plugin
does not retain a separate lower-level cache, but it is not a portable bridge
between the two APIs. Prefer one preferences API for every key.

A persistence operation reported as unsuccessful causes a
`PersistentSetPersistenceException`; other platform errors are propagated.

### Migrating from 0.1

Replace imports of `package:persistent_set/persistent_string_set.dart` with the
public entry point: `package:persistent_set/persistent_set.dart`. The legacy
entry point remains as a deprecated compatibility shim.

Use `seedIfMissing` in new code. The deprecated `seedIfEmpty` name remains
source-compatible for 1.0. On `PersistentStringSet`, that deprecated parameter
also retains its old behavior of seeding an existing empty set; the new
`seedIfMissing` parameter never replaces an existing value, including an empty
one. Do not provide both names in the same call.

## Concurrency boundary

The default coordinator is isolate-local. `SharedPreferences` does not provide
an atomic compare-and-swap or read-modify-write transaction, so conflicting
writes to the same key from another isolate, another process, native code, or
code that bypasses the storage coordinator can still overwrite one another.

An isolate broker or advisory file lock could coordinate cooperating callers
on some platforms, but it would not make separate preference reads and writes
atomic or cover code that bypasses that lock. Removing the boundary requires a
backend that owns an atomic transaction or compare-and-swap operation.

Give each persistent-set key a single coordinated owner when using the default
backend. If the same key must be mutated across those boundaries, use storage
with database transactions or revision-based conflict detection instead.
External reads do not cause lost updates, but readers with their own caches may
need to refresh before observing a completed write.

## Testing

Run unit tests with `flutter test`. The example app contains a real-platform
migration test for the legacy and async `SharedPreferences` APIs. CI runs it on
Android, iOS, Linux, macOS, web, and Windows; local commands are described in
`example/README.md`.

`SharedPreferences.setMockInitialValues` configures the legacy preferences API,
not `SharedPreferencesAsync`. Pass the resulting instance to the persistent set
when using that standard test helper:

```dart
SharedPreferences.setMockInitialValues({
  'user_favorites': <String>['item_123'],
});
final preferences = await SharedPreferences.getInstance();
final favorites = await PersistentStringSet.create(
  'user_favorites',
  preferences: preferences,
);
```

Omitting `preferences` continues to use the default asynchronous adapter.
