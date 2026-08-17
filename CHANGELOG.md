## 1.0.1

* Declare Android, iOS, Linux, macOS, web, and Windows support explicitly so
  pub.dev does not classify the package as Android-only because of its
  Android-specific legacy-storage compatibility dependency.
* Use web-compatible wildcard callback parameters in the package and migration
  test.

## 1.0.0

### Breaking changes

* The minimum supported Flutter version is now 3.29.0, with Dart 3.7.0.
* Membership changes become visible only after the storage operation completes
  successfully; await mutation futures before reading updated membership.
* Reported persistence failures now throw and leave membership unchanged instead of retaining optimistic in-memory changes.
* Mutations refresh storage before applying changes, so even a no-op mutation now performs an asynchronous read and can report a read failure.
* The default adapter now uses `SharedPreferencesAsync`. Package writes
  therefore do not update the legacy global `SharedPreferences` cache, and
  legacy readers may remain stale even after `reload()` on platforms that keep
  a separate plugin-level cache.
* `SharedPreferences.setMockInitialValues` configures only the legacy preferences
  API. Tests that use it must pass the resulting `SharedPreferences` instance
  through the new `preferences` parameter; otherwise creation uses the default
  async adapter and does not observe those mock values.
* `toSet(reload: true)` now reads only values already observed by the current storage handle. Use `await reload()` for an authoritative platform read.
* Re-entering a mutation for the same storage key from inside a `mutate`
  callback now throws `StateError`. The default async storage also requires
  nested mutations of distinct keys to acquire those keys in lexicographically
  ascending order. The injected legacy `SharedPreferences` adapter rejects
  nested bundled-storage transactions because it serializes whole-cache
  reloads.

### Added

* Add `mutate()` for serialized, transactional membership updates with rollback on persistence failure.
* Add `reload()` for authoritative asynchronous reads and deprecate `toSet(reload: true)`.
* Add `seedIfMissing` and deprecate the source-compatible `seedIfEmpty` alias. The deprecated `PersistentStringSet` parameter retains its existing-empty seeding behavior.
* Add `PersistentSetPersistenceException` for failed writes and removals.
* Expose the transactional storage contracts through the opt-in
  `package:persistent_set/persistent_set_storage.dart` entry point and accept
  custom storage through both public create methods. The outer storage contract
  exposes only its last-observed read and transaction boundary; writes and
  removals are available only through a held transaction.
* Support custom legacy key prefixes through the public create methods.
* Allow injecting a legacy `SharedPreferences` instance for tests that use `SharedPreferences.setMockInitialValues`.
* Export `PersistentStringSet` alongside `PersistentSet` from `package:persistent_set/persistent_set.dart`.
* Retain the deprecated `package:persistent_set/persistent_string_set.dart`
  entry point as a compatibility shim.

### Reliability and compatibility

* Coordinate mutations across instances and across the bundled async and legacy adapters when they share a storage namespace and key.
* Refresh persisted membership before mutations so stale instances cannot overwrite committed values.
* Retain the legacy Android backend and key prefix for data compatibility.
* Restore the legacy `SharedPreferences` cache after failed writes and removals.
* Preserve existing element instances during refresh when their encoded values are unchanged.
* Preserve subclass-provided set equality and iteration semantics in transaction drafts.
* Preserve invocation-time `addAll` iterable contents while mutations are queued.
* Avoid redundant serialization for no-op and queued convenience mutations.
* Release idle per-key lock state and scope observed-value caches to individual storage handles.

### Documentation and testing

* Document mutation lock duration, shallow transaction drafts, element immutability, and the cross-isolate, cross-process, and external-writer concurrency boundary.
* Add real-platform migration coverage for Android, iOS, Linux, macOS, web,
  and Windows.

## 0.1.0

* support persistent set for any type thanks to Qualle2911 contribution

## 0.0.1

* support PersistentStringSet
