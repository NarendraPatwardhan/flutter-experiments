import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bazel_hello/main.dart';

void main() {
  testWidgets('shows AgentOS host chrome', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('AgentOS on Flutter'), findsOneWidget);
    expect(
      find.textContaining('libghostty-vt'),
      findsWidgets,
    );
  });
}
