import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:persistent_set/persistent_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const key = 'persistent_set_real_platform_migration';

  Future<SharedPreferences> cleanPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    await preferences.remove(key);
    await preferences.reload();
    return preferences;
  }

  setUp(cleanPreferences);
  tearDown(cleanPreferences);

  testWidgets('0.1 values remain available through the async adapter', (
    final _,
  ) async {
    final legacyPreferences = await SharedPreferences.getInstance();
    await legacyPreferences.setStringList(key, ['legacy']);

    final set = await PersistentStringSet.create(key);
    expect(set.toSet().toList(), ['legacy']);

    await set.add('async');

    final recreated = await PersistentStringSet.create(key);
    expect(recreated.toSet().toList(), ['legacy', 'async']);
  });
}
