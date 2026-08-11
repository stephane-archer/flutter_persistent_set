import 'package:flutter_test/flutter_test.dart';
import 'package:persistent_set_example/main.dart';

void main() {
  testWidgets('renders the integration-test host', (final tester) async {
    await tester.pumpWidget(const PersistentSetExample());

    expect(find.text('Persistent Set integration tests'), findsOneWidget);
  });
}
