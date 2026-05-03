import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'config/dev_auth_config.dart';
import 'config/places_config.dart';
import 'theme/app_theme.dart';
import 'firebase_initializer_stub.dart' if (dart.library.io) 'firebase_initializer.dart' as firebase_init;
import 'services/auth_service.dart';
import 'services/navigation_service.dart';
import 'services/notification_service_stub.dart' if (dart.library.io) 'services/notification_service.dart';
import 'screens/auth/dev_auth_screen.dart';
import 'screens/auth/phone_auth_screen.dart';
import 'screens/auth/admin_login_screen.dart';
import 'screens/auth/not_registered_screen.dart';
import 'screens/auth/create_building_screen.dart';
import 'screens/building/pending_approval_screen.dart';
import 'screens/building/rejected_screen.dart';
import 'screens/spots/parking_spots_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'models/profile.dart';

// Detects the PKCE "Code verifier could not be found in local storage" error
// that can surface on web when a session is restored after a hard reload or
// a disrupted OAuth redirect. The implicit auth flow (configured below for
// web) prevents new occurrences, but stale sessions may still trigger it.
bool _isPkceVerifierError(Object error) {
  if (error is AuthException) {
    return error.message.toLowerCase().contains('code verifier');
  }
  return error.toString().toLowerCase().contains('code verifier');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  debugPrint('### MAIN STARTED ###');
  debugPrint('### TIME: ${DateTime.now().toIso8601String()} ###');

  // Initialize Firebase only on mobile (push notifications not supported on web)
  if (!kIsWeb) {
    try {
      await firebase_init.initializeFirebase();
    } catch (e) {
      debugPrint('Warning: Firebase initialization failed: $e');
      debugPrint(
        'Push notifications may not work. Make sure GoogleService-Info.plist (iOS) and google-services.json (Android) are configured.',
      );
    }
  }

  // Initialize Supabase
  if (!SupabaseConfig.isConfigured) {
    throw Exception(
      'Supabase configuration is missing. Please set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY for backward compatibility).',
    );
  }

  // ✅ DEBUG: Print Supabase configuration being used at runtime
  const supabaseUrl = SupabaseConfig.supabaseUrl;
  final supabasePublishableKey = SupabaseConfig.supabasePublishableKey;

  debugPrint('================ Supabase Runtime Config ================');
  debugPrint('SUPABASE_URL = $supabaseUrl');
  debugPrint(
    'SUPABASE_PUBLISHABLE_KEY starts with = ${supabasePublishableKey.isNotEmpty ? supabasePublishableKey.substring(0, 12) : "EMPTY"}',
  );
  if (SupabaseConfig.isPlaceholder) {
    debugPrint(
      '⚠️ Using placeholder config. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (e.g. .env + run_web.sh or --dart-define).',
    );
  }
  debugPrint('========================================================');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabasePublishableKey, // Supabase SDK still uses 'anonKey' parameter name
    // On web, use implicit flow so the OAuth callback does NOT require a PKCE
    // code-verifier to be persisted in localStorage.  The verifier can be lost
    // between the redirect and the callback page load (e.g. different tab,
    // storage cleared, privacy mode), causing the
    // "Code verifier could not be found in local storage" error.
    // On mobile the default PKCE flow is safe and preferred.
    authOptions: kIsWeb
        ? const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit)
        : const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );

  // Warn if Places API key is absent (address autocomplete will degrade gracefully).
  PlacesConfig.warnIfMissing();

  // Initialize notification service only on mobile (not supported on web)
  if (!kIsWeb) {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
    } catch (e) {
      debugPrint('Warning: Notification service initialization failed: $e');
    }
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('he'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('he'),
      startLocale: const Locale('he'),
      child: const ParkingTradeApp(),
    ),
  );
}

class ParkingTradeApp extends StatelessWidget {
  const ParkingTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Derive app-wide text direction from the active locale.
    // Hebrew ('he') is RTL; English ('en') is LTR.
    final isRtl = context.locale.languageCode == 'he';

    return MaterialApp(
      title: 'Parking Trade',
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const AuthWrapper(),
      routes: {
        '/auth': (context) => DevAuthConfig.isEnabled
            ? const DevAuthScreen()
            : const PhoneAuthScreen(),
        '/admin-login': (context) => const AdminLoginScreen(),
        '/not-registered': (context) => const NotRegisteredScreen(),
        '/pending-approval': (context) => const PendingApprovalScreen(),
        '/rejected': (context) => const RejectedScreen(),
        '/home': (context) => const ParkingSpotsScreen(),
        '/admin-dashboard': (context) => const AdminDashboardScreen(),
        '/setup': (context) => CreateBuildingScreen(
              onCreated: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil('/admin-dashboard', (route) => false),
            ),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  bool _isLoading = true;

  // Tracks whether a _navigateBasedOnProfile() call is currently in-flight.
  // Reset to false in the finally block so subsequent sign-in events (e.g.
  // tokenRefreshed) can always trigger a fresh navigation if needed.
  bool _navigating = false;

  // True once we have successfully navigated away from AuthWrapper.
  // Used to suppress redundant navigation calls (e.g. tokenRefreshed after
  // the initial signedIn already pushed /home).
  bool _hasNavigated = false;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('--- AuthWrapper: initState ---');

    // The auth stream always fires 'initialSession' on startup (with a session
    // if one is persisted, or null if not), so we rely entirely on the stream
    // for startup routing — no separate _checkAuth() call is needed.
    _authSubscription = _authService.authStateChanges.listen(
      (state) {
        debugPrint('--- AuthWrapper: authStateChange event=${state.event} ---');
        _handleAuthChange(state).catchError((error) {
          debugPrint('--- AuthWrapper: error handling auth change: $error ---');
          if (_isPkceVerifierError(error)) {
            debugPrint('--- AuthWrapper: PKCE verifier error in handler, clearing session ---');
            _clearSessionAndGoToAuth();
          } else {
            if (mounted) setState(() => _isLoading = false);
          }
        });
      },
      onError: (error) {
        debugPrint('--- AuthWrapper: auth stream error: $error ---');
        if (_isPkceVerifierError(error)) {
          // The PKCE code verifier was lost (e.g. hard reload during OAuth
          // redirect, privacy-mode storage, or a stale session from before the
          // implicit flow was enabled). Clear the broken session and send the
          // user back to the login screen instead of showing a blank/broken UI.
          debugPrint('--- AuthWrapper: PKCE verifier error detected, clearing session ---');
          _clearSessionAndGoToAuth();
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Silently signs out (best-effort) and routes to the login screen.
  ///
  /// Called when a PKCE verifier error is detected so the user sees the auth
  /// screen rather than an unhandled exception or a frozen loading spinner.
  Future<void> _clearSessionAndGoToAuth() async {
    try {
      await _authService.signOut();
    } catch (e) {
      // Sign-out can fail when the session is already invalid — that's fine,
      // we just want to clear local state.
      debugPrint('--- AuthWrapper: sign-out during PKCE recovery failed (expected): $e ---');
    }
    _hasNavigated = false;
    _navigating = false;
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    }
  }

  Future<void> _handleAuthChange(AuthState state) async {
    debugPrint('--- AuthWrapper: _handleAuthChange event=${state.event} hasNavigated=$_hasNavigated navigating=$_navigating ---');

    if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.tokenRefreshed) {

      if (_authService.currentSession != null) {
        // Skip navigation when the login screen already handled it imperatively
        // (signedIn) or when a token refresh fires while the user is already on
        // a post-login screen (tokenRefreshed).  Both cases are covered by the
        // _hasNavigated flag so we don't push a duplicate route.
        if (_hasNavigated &&
            (state.event == AuthChangeEvent.signedIn ||
             state.event == AuthChangeEvent.tokenRefreshed)) {
          debugPrint('--- AuthWrapper: ${state.event} after imperative navigation, skipping ---');
          return;
        }
        await _navigateBasedOnProfile();
      } else if (state.event == AuthChangeEvent.initialSession) {
        // initialSession fired but session is null → no stored session.
        debugPrint('--- AuthWrapper: initialSession with no session, showing auth ---');
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (state.event == AuthChangeEvent.signedOut) {
      debugPrint('--- AuthWrapper: signed out, routing to /auth ---');
      _hasNavigated = false;
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/auth',
          (route) => false,
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateBasedOnProfile() async {
    debugPrint('--- AuthWrapper: _navigateBasedOnProfile triggered, navigating=$_navigating hasNavigated=$_hasNavigated ---');

    // Prevent two concurrent profile-fetch + navigation calls.
    // NOTE: _hasNavigated is intentionally NOT checked here so that a
    // signedIn event after a sign-out can always re-navigate.
    if (_navigating) {
      debugPrint('--- AuthWrapper: already navigating, skipping ---');
      return;
    }
    _navigating = true;
    // Set speculatively before the async gap so any concurrent stream event
    // (e.g. signedIn arriving while we await the profile fetch) sees the flag
    // and skips a redundant navigation call.
    _hasNavigated = true;

    try {
      debugPrint('--- AuthWrapper: fetching profile... ---');
      final profile = await _authService.getCurrentProfile();
      debugPrint('--- AuthWrapper: profile fetched: $profile ---');

      if (!mounted) {
        debugPrint('--- AuthWrapper: widget unmounted after profile fetch, aborting ---');
        return;
      }

      // No pre-created profile found for this user.
      if (profile == null || profile.apartmentId == null) {
        if (profile != null && profile.isAdmin) {
          debugPrint('--- AuthWrapper: navigating to /admin-dashboard (admin, no apartment) ---');
          Navigator.of(context).pushNamedAndRemoveUntil('/admin-dashboard', (route) => false);
        } else {
          debugPrint('--- AuthWrapper: navigating to /not-registered ---');
          Navigator.of(context).pushNamedAndRemoveUntil('/not-registered', (route) => false);
        }
        return;
      }

      if (profile.isAdmin) {
        debugPrint('--- AuthWrapper: navigating to /admin-dashboard ---');
        Navigator.of(context).pushNamedAndRemoveUntil('/admin-dashboard', (route) => false);
      } else if (profile.status == ProfileStatus.pending) {
        debugPrint('--- AuthWrapper: navigating to /pending-approval ---');
        Navigator.of(context).pushNamedAndRemoveUntil('/pending-approval', (route) => false);
      } else if (profile.status == ProfileStatus.rejected) {
        debugPrint('--- AuthWrapper: navigating to /rejected ---');
        Navigator.of(context).pushNamedAndRemoveUntil('/rejected', (route) => false);
      } else {
        debugPrint('--- AuthWrapper: navigating to /home ---');
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      debugPrint('--- AuthWrapper: error in _navigateBasedOnProfile: $e ---');
      if (!mounted) return;
      final user = _authService.currentUser;
      if (user == null) {
        // No user — reset so the next real login can navigate.
        _hasNavigated = false;
        Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/not-registered', (route) => false);
      }
    } finally {
      // Always reset the in-flight guard so future sign-in events can navigate.
      _navigating = false;
      if (mounted) setState(() => _isLoading = false);
      debugPrint('--- AuthWrapper: _navigateBasedOnProfile done, navigating=false ---');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DevAuthConfig.isEnabled ? const DevAuthScreen() : const PhoneAuthScreen();
  }
}
 
