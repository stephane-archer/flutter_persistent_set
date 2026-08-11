import 'package:flutter/widgets.dart';

void main() => runApp(const PersistentSetExample());

class PersistentSetExample extends StatelessWidget {
  const PersistentSetExample({super.key});

  @override
  Widget build(final BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Persistent Set integration tests')),
    );
  }
}
