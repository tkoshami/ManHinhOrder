import 'package:flutter_test/flutter_test.dart';
import 'package:pos_fnb/main.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Note: Supabase.initialize usually needs to be mocked in a real test environment,
    // but for a basic smoke test, we check if the main widget tree can be built.
    await tester.pumpWidget(const MyApp());

    // Verify that the login screen appears by checking for the app name
    expect(find.text('MarPOS'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
  });
}
