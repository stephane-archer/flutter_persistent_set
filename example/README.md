# Persistent Set integration tests

This app exercises `persistent_set` through the real `shared_preferences`
platform plugins. The same migration test runs on Android, iOS, Linux, macOS,
web, and Windows. All platform hosts are generated on demand so they do not add
platform scaffolding to the published package. Generate the host you need
before running its test:

```sh
flutter create --platforms=macos .
flutter test integration_test/persistence_migration_test.dart -d macos
flutter create --platforms=android .
flutter test integration_test/persistence_migration_test.dart -d <android-device>
flutter create --platforms=ios .
flutter test integration_test/persistence_migration_test.dart -d <ios-simulator>
flutter create --platforms=linux .
flutter test integration_test/persistence_migration_test.dart -d linux
flutter create --platforms=web .
chromedriver --port=4444
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/persistence_migration_test.dart \
  --headless -d web-server
flutter create --platforms=windows .
flutter test integration_test/persistence_migration_test.dart -d windows
```

The test writes data through the legacy API used by package version 0.1, reads
and mutates it through the new async adapter, then confirms that a recreated
persistent set observes the committed values.
