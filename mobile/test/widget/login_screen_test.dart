import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:namma_kural/data/api_client.dart';
import 'package:namma_kural/domain/models/citizen_user.dart';
import 'package:namma_kural/features/login/login_screen.dart';
import 'package:namma_kural/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake backend for the phase-1 login protocol: one registered account
/// (9876543210 → "Chinmay Sai"); any other phone auto-registers.
class _FakeApi implements ApiClient {
  final Map<String, String> registered = {'9876543210': 'Chinmay Sai'};
  int loginCalls = 0;

  @override
  Future<CitizenUser> citizenLogin(
      {required String name, required String phone}) async {
    loginCalls++;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final clean = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    final existing = registered[clean];
    if (existing != null) {
      if (existing.toLowerCase() != name.trim().toLowerCase()) {
        throw const ApiException(
            'This mobile number is already registered under a different name. '
            'Enter the name it was registered with.');
      }
      return CitizenUser(id: 'u-$clean', name: existing, phone: clean);
    }
    registered[clean] = name.trim();
    return CitizenUser(id: 'u-$clean', name: name.trim(), phone: clean, created: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Widget, ProviderContainer, _FakeApi)> harness() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(api),
      ],
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
    return (app, container, api);
  }

  Future<void> fillAndSendOtp(WidgetTester tester,
      {required String name, required String phone}) async {
    await tester.enterText(
        find.widgetWithText(TextField, 'As per your records'), name);
    await tester.enterText(
        find.widgetWithText(TextField, '98xxx xxxxx'), phone);
    await tester.pump();
    await tester.tap(find.text('Send OTP'));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('old dummy credentials are gone; new protocol fields render',
      (tester) async {
    final (app, container, _) = await harness();
    await tester.pumpWidget(app);

    expect(find.text('CITIZEN SIGN IN'), findsOneWidget);
    expect(find.text('One account per mobile number'), findsOneWidget);
    // Removed phase-0 dummy flow:
    expect(find.text('Continue as Raj Kumar'), findsNothing);
    expect(find.text('Aadhaar'), findsNothing);
    expect(find.text('PASSWORD'), findsNothing);
    // OTP hidden until requested.
    expect(find.text('ENTER OTP'), findsNothing);

    container.dispose();
  });

  testWidgets('new phone auto-registers and lands on home', (tester) async {
    final (app, container, api) = await harness();
    await tester.pumpWidget(app);

    await fillAndSendOtp(tester, name: 'Meena Devi', phone: '9000011111');
    expect(find.textContaining('demo code 246813'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '••••••'), '246813');
    await tester.pump();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(api.registered['9000011111'], 'Meena Devi');
    expect(container.read(authProvider), isTrue);
    expect(container.read(prefsProvider).accountId, 'u-9000011111');
    expect(container.read(prefsProvider).citizenName, 'Meena Devi');
    expect(container.read(userIdProvider), 'u-9000011111');
    expect(find.text('HOME STUB'), findsOneWidget);

    container.dispose();
  });

  testWidgets('registered phone with matching name signs in', (tester) async {
    final (app, container, api) = await harness();
    await tester.pumpWidget(app);

    await fillAndSendOtp(tester, name: 'chinmay sai', phone: '98765 43210');
    await tester.enterText(find.widgetWithText(TextField, '••••••'), '246813');
    await tester.pump();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(api.loginCalls, 1);
    expect(container.read(authProvider), isTrue);
    // Canonical name from the backend record wins.
    expect(container.read(prefsProvider).citizenName, 'Chinmay Sai');
    expect(find.text('HOME STUB'), findsOneWidget);

    container.dispose();
  });

  testWidgets('registered phone with a DIFFERENT name is rejected',
      (tester) async {
    final (app, container, _) = await harness();
    await tester.pumpWidget(app);

    await fillAndSendOtp(tester, name: 'Someone Else', phone: '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '••••••'), '246813');
    await tester.pump();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(container.read(authProvider), isFalse);
    expect(find.text('HOME STUB'), findsNothing);
    expect(
        find.textContaining('registered under a different name'), findsOneWidget);

    container.dispose();
  });

  testWidgets('wrong OTP never reaches the backend', (tester) async {
    final (app, container, api) = await harness();
    await tester.pumpWidget(app);

    await fillAndSendOtp(tester, name: 'Meena Devi', phone: '9000011111');
    await tester.enterText(find.widgetWithText(TextField, '••••••'), '111111');
    await tester.pump();
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.loginCalls, 0);
    expect(container.read(authProvider), isFalse);
    expect(find.textContaining('Incorrect OTP'), findsOneWidget);

    container.dispose();
  });
}
