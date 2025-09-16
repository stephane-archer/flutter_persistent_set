# Persistent String Set

A simple Dart package that provides a `Set<String>` like interface which is persisted on the device. This is useful for managing a collection of unique strings that need to be saved across app launches, such as user favorites or tags.

## Features

- Provides a `Set`-like API for managing a collection of strings.
- Automatically persists changes to device storage.
- Simple and easy to use.

## Getting started

Add the package to your `pubspec.yaml`:

```bash
flutter pub add persistent_string_set
```

Or add it manually:

```yaml
dependencies:
  persistent_string_set: ^latest_version # Replace with the latest version
```

## Usage

Here's an example of how you might use `PersistentStringSet` to manage a user's favorite items in an application. You can wrap it in a service class for easy management.

```dart
import 'package:persistent_string_set/persistent_string_set.dart';

/// A service to manage user's favorite items.
class FavoritesService {
  late final PersistentStringSet _favorites;
  bool _isInitialized = false;

  // A unique key to store the favorites in persistent storage.
  static const _favoritesKey = 'user_favorites';

  /// Initializes the service by loading the favorites from storage.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _favorites = await PersistentStringSet.create(_favoritesKey);
    _isInitialized = true;
  }

  /// Adds an item to the user's favorites.
  Future<void> addFavorite(String itemId) async {
    await _favorites.add(itemId);
  }

  /// Removes an item from the user's favorites.
  Future<void> removeFavorite(String itemId) async {
    await _favorites.remove(itemId);
  }

  /// Checks if an item is in the user's favorites.
  bool isFavorite(String itemId) {
    // Throws if the service is not initialized.
    return _favorites.contains(itemId);
  }

  /// Returns a copy of all favorite items.
  Set<String> getFavorites() {
    return _favorites.toSet();
  }
  
  /// Returns the number of favorite items.
  int get favoritesCount => _favorites.length;
}

// Example of how to use the service
void main() async {
  // You would typically initialize your services once when the app starts.
  final favoritesService = FavoritesService();
  await favoritesService.initialize();

  // Now you can use the service to manage favorites across your app.
  print('Adding item_123 to favorites...');
  await favoritesService.addFavorite('item_123');
  print('Is item_123 a favorite? ${favoritesService.isFavorite('item_123')}'); // true
  print('Total favorites: ${favoritesService.favoritesCount}'); // 1

  print('Adding item_456 to favorites...');
  await favoritesService.addFavorite('item_456');
  print('Total favorites: ${favoritesService.favoritesCount}'); // 2

  // The data persists. If you restart the app and initialize the service again,
  // the favorites will still be there.

  print('Removing item_123 from favorites...');
  await favoritesService.removeFavorite('item_123');
  print('Is item_123 a favorite? ${favoritesService.isFavorite('item_123')}'); // false
  print('Total favorites: ${favoritesService.favoritesCount}'); // 1
}
```
