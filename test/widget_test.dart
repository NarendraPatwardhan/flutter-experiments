import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bazel_hello/main.dart';

void main() {
  testWidgets('shows greeting', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Hello, Linux'), findsOneWidget);
    expect(find.textContaining('ready to morph'), findsOneWidget);
    expect(find.textContaining('rules_flutter'), findsOneWidget);
  });
}
