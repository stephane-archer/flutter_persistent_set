// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:persistent_set/persistent_string_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy entry point continues to export PersistentStringSet', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final set = await PersistentStringSet.create(
      'legacy_entrypoint',
      preferences: preferences,
    );

    await set.add('value');
    expect(set.toSet(), {'value'});
  });
}
