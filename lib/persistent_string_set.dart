import 'package:persistent_set/persistent_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

// @Deprecated('Use PersistentSet.create<String>(key) instead')
// Deprecate after resolving TOD0 in persistent_set.dart;
// this class will remain for backward compatibility and easy of use for strings.
class PersistentStringSet extends PersistentSet<String> {
  PersistentStringSet._(String key, Set<String> mem, SharedPreferences prefs)
    : super.internal(key, mem, prefs, (s) => s, (s) => s);

  /// Create or load a persistent set of strings at `key`.
  /// If the key does not exist and `seedIfEmpty` is provided, it will be used to
  /// initialize the set and persist it immediately.
  static Future<PersistentStringSet> create(
    String key, {
    Set<String>? seedIfEmpty,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key);
    final mem = (list != null) ? list.toSet() : <String>{};
    final set = PersistentStringSet._(key, mem, prefs);
    if (mem.isEmpty && seedIfEmpty != null) {
      await set.addAll(seedIfEmpty);
    }
    return set;
  }
}
