import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:namma_kural/features/login/login_screen.dart';
import 'package:namma_kural/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Widget, ProviderContainer)> harness() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/home',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('HOME STUB'))),
        ),
      ],
    );
    final app = UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
    return (app, container);
  }

  testWidgets('renders the brand, mock-OTP hint flow and demo pill',
      (tester) async {
    final (app, container) = await harness();
    await tester.pumpWidget(app);

    expect(find.text('CITIZEN SIGN IN'), findsOneWidget);
    // OTP field hidden until Send OTP
    expect(find.text('ENTER OTP'), findsNothing);

    // Demo pill lives below the fold — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Continue as Raj Kumar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Continue as Raj Kumar'), findsOneWidget);

    container.dispose();
  });

  testWidgets('Send OTP reveals the mock-OTP field with the demo code hint',
      (tester) async {
    final (app, container) = await harness();
    await tester.pumpWidget(app);

    // Type a 10-digit mobile then send OTP.
    await tester.enterText(
        find.widgetWithText(TextField, '98xxx xxxxx').first, '9884012345');
    await tester.pump();
    await tester.tap(find.text('Send OTP'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ENTER OTP'), findsOneWidget);
    expect(find.textContaining('demo code 246813'), findsOneWidget);

    container.dispose();
  });

  testWidgets('demo pill autofills, signs in and lands on home',
      (tester) async {
    final (app, container) = await harness();
    await tester.pumpWidget(app);

    expect(container.read(authProvider), isFalse);

    await tester.scrollUntilVisible(
      find.text('Continue as Raj Kumar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue as Raj Kumar'));
    // demo login waits 400ms before navigating
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(authProvider), isTrue);
    expect(container.read(prefsProvider).citizenName, 'Raj Kumar');
    expect(find.text('HOME STUB'), findsOneWidget);

    container.dispose();
  });
}
