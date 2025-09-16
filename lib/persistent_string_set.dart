import 'package:shared_preferences/shared_preferences.dart';

class PersistentStringSet {
  final String _key;
  final Set<String> _setInMemory;
  final SharedPreferences _prefs;

  PersistentStringSet._(this._key, this._setInMemory, this._prefs);

  int get length => _setInMemory.length;

  Future<bool> add(String value) async {
    final bool added = _setInMemory.add(value);
    if (added) {
      await _prefs.setStringList(_key, _setInMemory.toList());
    }
    return added;
  }

  Future<void> clear() async {
    _setInMemory.clear();
    await _prefs.remove(_key);
  }

  bool contains(Object? element) {
    return _setInMemory.contains(element);
  }

  String? lookup(Object? element) {
    return _setInMemory.lookup(element);
  }

  Future<bool> remove(Object? value) async {
    final bool removed = _setInMemory.remove(value);
    if (removed) {
      await _prefs.setStringList(_key, _setInMemory.toList());
    }
    return removed;
  }

  Set<String> toSet() {
    return _setInMemory.toSet();
  }

  static Future<PersistentStringSet> create(String key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? items = prefs.getStringList(key);
    final setInMemory = items?.toSet() ?? <String>{};
    return PersistentStringSet._(key, setInMemory, prefs);
  }
}
