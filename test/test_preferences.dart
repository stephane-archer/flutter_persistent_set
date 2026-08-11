import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Installs legacy and async shared-preferences test stores over the same data.
///
/// Production implementations expose the same platform data through both APIs;
/// the package's stock in-memory fakes use separate stores, so tests need this
/// shared backing map when exercising both APIs together.
void setMockInitialPreferences(final Map<String, Object> values) {
  final data = _SharedPreferenceData(values);
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = _LegacyPreferenceStore(data);
  SharedPreferencesAsyncPlatform.instance = _AsyncPreferenceStore(data);
}

final class _SharedPreferenceData {
  final Map<String, Object> values;

  _SharedPreferenceData(final Map<String, Object> values)
    : values = values.map(
        (final key, final value) => MapEntry(key, _copyValue(value)),
      );
}

final class _LegacyPreferenceStore extends SharedPreferencesStorePlatform {
  final _SharedPreferenceData _data;

  _LegacyPreferenceStore(this._data);

  @override
  Future<bool> clear() async {
    _data.values.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    return {
      for (final entry in _data.values.entries)
        'flutter.${entry.key}': _copyValue(entry.value),
    };
  }

  @override
  Future<bool> remove(final String key) async {
    _data.values.remove(_legacyKey(key));
    return true;
  }

  @override
  Future<bool> setValue(
    final String valueType,
    final String key,
    final Object value,
  ) async {
    _data.values[_legacyKey(key)] = _copyValue(value);
    return true;
  }
}

final class _AsyncPreferenceStore extends SharedPreferencesAsyncPlatform {
  final _SharedPreferenceData _data;

  _AsyncPreferenceStore(this._data);

  @override
  Future<void> clear(
    final ClearPreferencesParameters parameters,
    final SharedPreferencesOptions options,
  ) async {
    final allowList = parameters.filter.allowList;
    if (allowList == null) {
      _data.values.clear();
    } else {
      final logicalKeys = allowList.map(_asyncKey).toSet();
      _data.values.removeWhere(
        (final key, final _) => logicalKeys.contains(key),
      );
    }
  }

  @override
  Future<bool?> getBool(
    final String key,
    final SharedPreferencesOptions options,
  ) async => _data.values[_asyncKey(key)] as bool?;

  @override
  Future<double?> getDouble(
    final String key,
    final SharedPreferencesOptions options,
  ) async => _data.values[_asyncKey(key)] as double?;

  @override
  Future<int?> getInt(
    final String key,
    final SharedPreferencesOptions options,
  ) async => _data.values[_asyncKey(key)] as int?;

  @override
  Future<Set<String>> getKeys(
    final GetPreferencesParameters parameters,
    final SharedPreferencesOptions options,
  ) async {
    final allowList = parameters.filter.allowList;
    return _data.values.keys
        .map((final key) => 'flutter.$key')
        .where((final key) => allowList == null || allowList.contains(key))
        .toSet();
  }

  @override
  Future<Map<String, Object>> getPreferences(
    final GetPreferencesParameters parameters,
    final SharedPreferencesOptions options,
  ) async {
    final allowList = parameters.filter.allowList;
    return {
      for (final entry in _data.values.entries)
        if (allowList == null || allowList.contains('flutter.${entry.key}'))
          'flutter.${entry.key}': _copyValue(entry.value),
    };
  }

  @override
  Future<String?> getString(
    final String key,
    final SharedPreferencesOptions options,
  ) async => _data.values[_asyncKey(key)] as String?;

  @override
  Future<List<String>?> getStringList(
    final String key,
    final SharedPreferencesOptions options,
  ) async {
    final value = _data.values[_asyncKey(key)] as List<Object?>?;
    return value?.cast<String>().toList(growable: false);
  }

  @override
  Future<void> setBool(
    final String key,
    final bool value,
    final SharedPreferencesOptions options,
  ) async {
    _data.values[_asyncKey(key)] = value;
  }

  @override
  Future<void> setDouble(
    final String key,
    final double value,
    final SharedPreferencesOptions options,
  ) async {
    _data.values[_asyncKey(key)] = value;
  }

  @override
  Future<void> setInt(
    final String key,
    final int value,
    final SharedPreferencesOptions options,
  ) async {
    _data.values[_asyncKey(key)] = value;
  }

  @override
  Future<void> setString(
    final String key,
    final String value,
    final SharedPreferencesOptions options,
  ) async {
    _data.values[_asyncKey(key)] = value;
  }

  @override
  Future<void> setStringList(
    final String key,
    final List<String> value,
    final SharedPreferencesOptions options,
  ) async {
    _data.values[_asyncKey(key)] = List<String>.of(value, growable: false);
  }
}

String _legacyKey(final String key) {
  const prefix = 'flutter.';
  return key.startsWith(prefix) ? key.substring(prefix.length) : key;
}

String _asyncKey(final String key) => _legacyKey(key);

Object _copyValue(final Object value) {
  return value is List<Object?> ? List<Object?>.of(value) : value;
}
