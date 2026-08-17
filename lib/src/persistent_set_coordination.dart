import 'dart:async';

import 'package:meta/meta.dart' show internal;

@internal
final class PersistentStorageCoordinator {
  final Map<String, StorageOperationQueue> _keyQueues = {};
  final Object _zoneKey = Object();

  Future<R> run<R>(final String key, final Future<R> Function() operation) {
    final currentContext = Zone.current[_zoneKey];
    if (currentContext is _CoordinatorOperationContext &&
        currentContext.isActive &&
        key.compareTo(currentContext.lastKey) <= 0) {
      throw StateError(
        'Cannot acquire persistent storage key "$key" while '
        '"${currentContext.lastKey}" is locked. Nested transactions must '
        'acquire distinct keys in ascending order.',
      );
    }

    final queue = _keyQueues.putIfAbsent(key, StorageOperationQueue.new);
    final result = queue.run(() {
      final context = _CoordinatorOperationContext(key);
      return runZoned(
        operation,
        zoneValues: {_zoneKey: context},
      ).whenComplete(() => context.isActive = false);
    });
    return result.whenComplete(() {
      if (queue.isIdle && identical(_keyQueues[key], queue)) {
        _keyQueues.remove(key);
      }
    });
  }
}

final class _CoordinatorOperationContext {
  final String lastKey;
  var isActive = true;

  _CoordinatorOperationContext(this.lastKey);
}

@internal
final class StorageOperationQueue {
  final Object _zoneKey = Object();
  final bool _allowReentrant;
  var _tail = Future<void>.value();
  var _operationCount = 0;

  StorageOperationQueue({final bool allowReentrant = false})
    : _allowReentrant = allowReentrant;

  bool get isIdle => _operationCount == 0;

  Future<R> run<R>(final Future<R> Function() operation) {
    final currentContext = Zone.current[_zoneKey];
    if (currentContext is _StorageOperationContext && currentContext.isActive) {
      if (_allowReentrant) {
        return Future<R>.sync(operation);
      }
      throw StateError(
        'Cannot start a nested persistent storage transaction for a key that '
        'is already locked.',
      );
    }

    _operationCount += 1;
    final result = _tail.then((_) => _run(operation));
    _tail = result.then<void>(
      (_) {},
      onError: (final Object _, final StackTrace _) {},
    );
    return result.whenComplete(() => _operationCount -= 1);
  }

  Future<R> _run<R>(final Future<R> Function() operation) async {
    final context = _StorageOperationContext();
    try {
      return await runZoned(operation, zoneValues: {_zoneKey: context});
    } finally {
      context.isActive = false;
    }
  }
}

final class _StorageOperationContext {
  var isActive = true;
}
