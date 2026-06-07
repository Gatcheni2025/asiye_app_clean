import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asiye_app/main.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: AsiyeMainShell()));

    // Verify that the initializing text is shown
    expect(find.textContaining('Initializing'), findsOneWidget);
  });
}
