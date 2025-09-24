# Persistent Set

A simple Dart package that provides a `Set<T>`-like interface which is persisted on the device. This is useful for managing a collection of unique values (strings, numbers, IDs, etc.) that need to be saved across app launches, such as user favorites, tags, or cached identifiers.

## Features

* Provides a `Set`-like API for managing a collection of values.
* Automatically persists changes to device storage.
* Simple and easy to use.

## Getting started

Add the package to your `pubspec.yaml`:

```bash
flutter pub add persistent_set
```

Or add it manually:

```yaml
dependencies:
  persistent_set: ^latest_version # Replace with the latest version
```

## Usage

Here’s an example of how you might use `PersistentSet<String>` to manage a user’s favorite items.
You can wrap it in a service class for easy management.

```dart
import 'package:persistent_set/persistent_set.dart';

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
  final favoritesService = FavoritesService();
  await favoritesService.initialize();

  print('Adding item_123 to favorites...');
  await favoritesService.addFavorite('item_123');
  print('Is item_123 a favorite? ${favoritesService.isFavorite('item_123')}'); // true
  print('Total favorites: ${favoritesService.favoritesCount}'); // 1
}
```

You can also use other types, for example:

```dart
final visitedPages = await PersistentSet.create<int>('visited_pages', toJson: (v) => v.toString(), fromJson: (s) => int.parse(s));
await visitedPages.add(42);
print(visitedPages.contains(42)); // true
```
