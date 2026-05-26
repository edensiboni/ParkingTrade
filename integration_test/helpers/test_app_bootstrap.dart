// integration_test/helpers/test_app_bootstrap.dart
//
// Central bootstrap for all integration / E2E tests.
//
// Usage in every test file:
//
//   void main() {
//     IntegrationTestWidgetsFlutterBinding.ensureInitialized();
//     group('My flow', () {
//       testWidgets('...', (tester) async {
//         await TestAppBootstrap.pump(tester);
//         ...
//       });
//     });
//   }
//
// Design goals
// ─────────────
//   • Mirrors main.dart exactly — same EasyLocalization wrapper, same routes,
//     same MaterialApp.  Tests run against real widget code, not stubs.
//   • Supabase is initialised once per process via a guard flag.  Calling
//     TestAppBootstrap.pump() from multiple tests is safe.
//   • Firebase is skipped in the test environment to avoid needing real
//     google-services.json / GoogleService-Info.plist at test time.
//   • All long animations are pumped to completion with a generous timeout so
//     shimmer loaders and Material 3 page transitions don't leave the pump
//     loop hanging.

import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:parking_trade/config/supabase_config.dart';
import 'package:parking_trade/services/navigation_service.dart';
import 'package:parking_trade/theme/app_theme.dart';
import 'package:parking_trade/screens/auth/phone_auth_screen.dart';
import 'package:parking_trade/screens/auth/admin_login_screen.dart';
import 'package:parking_trade/screens/auth/not_registered_screen.dart';
import 'package:parking_trade/screens/auth/create_building_screen.dart';
import 'package:parking_trade/screens/building/pending_approval_screen.dart';
import 'package:parking_trade/screens/building/rejected_screen.dart';
import 'package:parking_trade/screens/spots/parking_spots_screen.dart';
import 'package:parking_trade/screens/admin/admin_dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Guards
// ─────────────────────────────────────────────────────────────────────────────

bool _supabaseInitialised = false;

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap helper
// ─────────────────────────────────────────────────────────────────────────────

class TestAppBootstrap {
  TestAppBootstrap._();

  /// Pumps the full [ParkingTradeTestApp] into [tester] and settles all
  /// pending animations/frames, then returns.
  ///
  /// [locale] defaults to Hebrew (he) — the app's production default.
  /// Pass `Locale('en')` to exercise the English locale branch.
  ///
  /// [pumpSettleTimeout] controls the maximum time given to
  /// [WidgetTester.pumpAndSettle] for the initial paint.  Increase it if
  /// shimmer / onboarding animations are very long on a slow CI machine.
  static Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('he'),
    Duration pumpSettleTimeout = const Duration(seconds: 10),
  }) async {
    await ensureSupabase();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('he'), Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('he'),
        startLocale: locale,
        // Disable asset loading in tests — translations are loaded from the
        // real assets directory that flutter test mounts automatically.
        child: const _ParkingTradeTestApp(),
      ),
    );

    // Let EasyLocalization finish loading the translation JSON and let
    // MaterialApp complete its first frame.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      pumpSettleTimeout,
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Exposed internally so test helpers in the same package can call it
  /// (e.g. _pumpHeroCard in app_e2e_test.dart).
  static Future<void> ensureSupabase() async {
    if (_supabaseInitialised) return;

    // In CI / unit-test environments the --dart-define values are often not
    // injected.  We fall back to dummy values so the SDK initialises without
    // throwing.  Actual network calls will fail with auth errors, which is
    // expected and handled per-test via mocks or the fake-auth helper.
    final url = SupabaseConfig.supabaseUrl.isNotEmpty
        ? SupabaseConfig.supabaseUrl
        : 'https://placeholder.supabase.co';
    final key = SupabaseConfig.supabasePublishableKey.isNotEmpty
        ? SupabaseConfig.supabasePublishableKey
        : 'placeholder-anon-key';

    await Supabase.initialize(
      url: url,
      anonKey: key,
      authOptions:
          const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    _supabaseInitialised = true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test-only MaterialApp
//
// Identical route table to the production ParkingTradeApp but:
//   • Uses the AuthWrapper-less route so tests control the starting screen.
//   • Starts on PhoneAuthScreen (unauthenticated entry point).
// ─────────────────────────────────────────────────────────────────────────────

class _ParkingTradeTestApp extends StatelessWidget {
  const _ParkingTradeTestApp();

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'he';

    return MaterialApp(
      title: 'ParkingTrade [Test]',
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => Directionality(
        textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child!,
      ),
      // Tests start on the phone-auth screen (unauthenticated state).
      home: const PhoneAuthScreen(),
      routes: {
        '/auth': (_) => const PhoneAuthScreen(),
        '/admin-login': (_) => const AdminLoginScreen(),
        '/not-registered': (_) => const NotRegisteredScreen(),
        '/pending-approval': (_) => const PendingApprovalScreen(),
        '/rejected': (_) => const RejectedScreen(),
        '/home': (_) => const ParkingSpotsScreen(),
        '/admin-dashboard': (_) => const AdminDashboardScreen(),
        '/setup': (context) => CreateBuildingScreen(
              onCreated: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil('/admin-dashboard', (r) => false),
            ),
      },
    );
  }
}
