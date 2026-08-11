/// Advanced storage contracts for custom `PersistentSet` backends.
///
/// Most applications should use the default SharedPreferences backend exposed
/// through `package:persistent_set/persistent_set.dart`.
library;

export 'src/persistent_set_storage.dart'
    show PersistentSetStorage, PersistentSetStorageTransaction;
