import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistentSet<T> {
  final String _key;
  final Set<T> _mem;
  final SharedPreferences _prefs;
  final String Function(T value) _to;
  final T Function(String encoded) _from;

  /// Internal constructor for use when the set is already loaded.
  /// Use [create] to create or load a persistent set.
  /// This is used for subclassing (e.g. PersistentStringSet).
  @protected
  PersistentSet.internal(
    this._key,
    this._mem,
    this._prefs,
    this._to,
    this._from,
  );

  int get length => _mem.length;

  bool contains(T? element) => _mem.contains(element);

  /// Set.lookup preserves the actual stored instance (useful if T overrides ==).
  T? lookup(T? element) => _mem.lookup(element);

  /// Access a copy of the set.
  /// [reload] forces a reload from SharedPreferences.
  /// This is rarely needed, as the each instance is expected to be the sole
  /// modifier of its key. If multiple instances modify the same key,
  /// use [reload] to get the latest value.
  Set<T> toSet({bool reload = false}) =>
      reload ? _reloadRaw() : Set<T>.from(_mem);

  /// Add [value] to the set. Returns true if the value was not already present.
  /// If the set was modified, it is persisted immediately.
  Future<bool> add(T value) async {
    final added = _mem.add(value);
    if (added) await _persist();
    return added;
  }

  /// Add all [values] to the set. If the set was modified, it is persisted
  /// immediately.
  /// If [values] is empty or all values are already present, no write occurs.
  /// This method is more efficient than calling [add] repeatedly.
  Future<void> addAll(Iterable<T> values) async {
    final before = _mem.length;
    _mem.addAll(values);
    if (_mem.length != before) await _persist();
  }

  /// Remove [value] from the set. Returns true if the value was present.
  /// If the set was modified, it is persisted immediately.
  /// If [value] is null, does nothing and returns false.
  Future<bool> remove(T? value) async {
    final removed = _mem.remove(value);
    if (removed) await _persist();
    return removed;
  }

  /// Remove all elements that match the given [test].
  /// If the set was modified, it is persisted immediately.
  /// If no elements match, no write occurs.
  Future<void> removeWhere(bool Function(T) test) async {
    final before = _mem.length;
    _mem.removeWhere(test);
    if (_mem.length != before) await _persist();
  }

  /// Remove all elements from the set and removes the key from SharedPreferences.
  Future<void> clear() async {
    _mem.clear();
    await _prefs.remove(_key);
  }

  Future<void> _persist() async {
    final list = _mem.map(_to).toList(growable: false);
    await _prefs.setStringList(_key, list);
  }

  Set<T> _reloadRaw() {
    final raw = _prefs.getStringList(_key);
    return (raw != null) ? raw.map(_from).toSet() : <T>{};
  }

  /// Create or load a persistent set at `key`.
  /// You must provide functions to convert between T and String.
  /// If T is String, use (s) => s for both [to] and
  /// [from] (see PersistentStringSet).
  /// If the key does not exist and `seedIfEmpty` is provided, it will
  /// be used to initialize the set and persist it immediately.
  static Future<PersistentSet<T>> create<T>(
    String key, {
    // Todo: consider making them nullable and using a helper to silent handle T == int || double || bool || String, would simplify usage for those types and enable dropping the persistent_string_set.dart file.
    required String Function(T value) to,
    required T Function(String encoded) from,
    // If the key does not exist and `seedIfEmpty` is provided, it will be used to
    // initialize the set and persist it immediately.
    Iterable<T>? seedIfEmpty,
  }) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(key);

    final mem = <T>{};
    if (raw != null) {
      for (final s in raw) {
        mem.add(from(s));
      }
    } else if (seedIfEmpty != null) {
      mem.addAll(seedIfEmpty);
      // persist the seed immediately so subsequent app launches see it
      await p.setStringList(key, seedIfEmpty.map(to).toList(growable: false));
    }

    return PersistentSet.internal(key, mem, p, to, from);
  }
}