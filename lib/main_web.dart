// Web entry point. Optional Firebase web config enables browser push (FCM).
// Use: flutter run -d chrome -t lib/main_web.dart
//      flutter build web -t lib/main_web.dart

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/firebase_options_web.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/notification_service_web.dart';
import 'screens/auth/phone_auth_screen.dart';
import 'screens/auth/create_building_screen.dart';
import 'screens/auth/not_registered_screen.dart';
import 'screens/building/pending_approval_screen.dart';
import 'screens/building/rejected_screen.dart';
import 'screens/spots/parking_spots_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'models/profile.dart';

void main() async {
  // Set up error handlers to catch and display errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  // Handle async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error');
    debugPrint('Stack: $stack');
    return true;
  };

  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('### MAIN STARTED (web) ###');

    if (!SupabaseConfig.isConfigured) {
      runApp(const ErrorApp(
        'Supabase configuration is missing.\n\n'
        'Please set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY\n'
        '(or SUPABASE_ANON_KEY for backward compatibility)\n'
        'via .env + run_web.sh or --dart-define.',
      ));
      return;
    }

    const supabaseUrl = SupabaseConfig.supabaseUrl;
    final supabasePublishableKey = SupabaseConfig.supabasePublishableKey;
    debugPrint('Supabase URL = $supabaseUrl');
    if (SupabaseConfig.isPlaceholder) {
      debugPrint(
        '⚠️ Using placeholder Supabase config. Edit .env with real URL and publishable key (Supabase Dashboard → Project Settings → API).',
      );
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabasePublishableKey, // Supabase SDK still uses 'anonKey' parameter name
      );
    } catch (e) {
      runApp(ErrorApp(
        'Failed to initialize Supabase:\n\n$e\n\n'
        'Please check your SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      ));
      return;
    }

    // Handle the OAuth PKCE callback: when Google redirects back with
    // ?code=… in the URL, exchange the code for a session so it is stored in
    // localStorage.  Without this call the "Code verifier could not be found"
    // error occurs because the Supabase client hasn't yet exchanged the code.
    // The SDK's onAuthStateChange will fire signedIn once this completes.
    if (kIsWeb) {
      final uri = Uri.base;
      if (uri.queryParameters.containsKey('code')) {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(uri);
        } catch (e) {
          debugPrint('OAuth code exchange failed: $e');
          // Non-fatal — the auth state listener will route to /auth if needed.
        }
      }
    }

    if (FirebaseOptionsWeb.isConfigured) {
      try {
        await Firebase.initializeApp(options: FirebaseOptionsWeb.options);
        await WebNotificationService().initialize();
      } catch (e) {
        debugPrint('Firebase/Web push init failed: $e');
        // Continue even if Firebase fails - it's optional
      }
    }

    runApp(const ParkingTradeApp());
  } catch (e, stackTrace) {
    debugPrint('Fatal error in main: $e');
    debugPrint('Stack: $stackTrace');
    runApp(ErrorApp('Fatal error:\n\n$e'));
  }
}

class ParkingTradeApp extends StatelessWidget {
  const ParkingTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parking Trade',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
      routes: {
        '/auth': (context) => const PhoneAuthScreen(),
        '/setup': (context) => CreateBuildingScreen(
              onCreated: () =>
                  Navigator.of(context).pushReplacementNamed('/auth'),
            ),
        '/not-registered': (context) => const NotRegisteredScreen(),
        '/pending-approval': (context) => const PendingApprovalScreen(),
        '/rejected': (context) => const RejectedScreen(),
        '/home': (context) => const ParkingSpotsScreen(),
        '/admin': (context) => const AdminDashboardScreen(),
      },
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String message;

  const ErrorApp(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parking Trade - Error',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Configuration Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
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
  bool _isSetupMode = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _isSetupMode = _detectSetupMode();
    _checkAuth();
    _authSubscription = _authService.authStateChanges.listen(
      (state) {
        // Handle async operation properly to avoid promise rejection
        _handleAuthChange(state).catchError((error) {
          if (mounted) {
            debugPrint('Error handling auth change: $error');
          }
        });
      },
      onError: (error) {
        if (mounted) {
          debugPrint('Auth state stream error: $error');
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Returns true when the URL contains `mode=setup` (web only).
  bool _detectSetupMode() {
    if (!kIsWeb) return false;
    try {
      final uri = Uri.base;
      return uri.queryParameters['mode'] == 'setup';
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAuth() async {
    // Use currentSession (not just currentUser) so we confirm a valid,
    // persisted session exists before bypassing the phone auth screen.
    final session = _authService.currentSession;
    if (session != null) {
      await _navigateBasedOnProfile();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAuthChange(AuthState state) async {
    if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.tokenRefreshed) {
      // On app restart with a persisted session the SDK fires initialSession.
      // tokenRefreshed fires when the access token is silently renewed.
      // In all these cases we want to route based on the user's profile.
      if (_authService.currentSession != null) {
        await _navigateBasedOnProfile();
      } else if (state.event == AuthChangeEvent.initialSession) {
        // initialSession fired but session is null → no stored session, show auth.
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (state.event == AuthChangeEvent.signedOut) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/auth',
          (route) => false,
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateBasedOnProfile() async {
    try {
      final profile = await _authService.getCurrentProfile();

      if (!mounted) return;

      // No pre-created profile found for this phone number
      if (profile == null || profile.apartmentId == null) {
        Navigator.of(context).pushReplacementNamed('/not-registered');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Profile is linked to an apartment — route based on role then status
      if (profile.isAdmin) {
        // Building admins always go to the Admin Dashboard
        Navigator.of(context).pushReplacementNamed('/admin');
      } else if (profile.status == ProfileStatus.pending) {
        Navigator.of(context).pushReplacementNamed('/pending-approval');
      } else if (profile.status == ProfileStatus.rejected) {
        Navigator.of(context).pushReplacementNamed('/rejected');
      } else {
        // approved regular member → go to parking spots
        Navigator.of(context).pushReplacementNamed('/home');
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error navigating based on profile: $e');
      final user = _authService.currentUser;
      if (user == null && mounted) {
        Navigator.of(context).pushReplacementNamed('/auth');
      } else if (mounted) {
        // Authenticated but profile fetch failed — treat as not registered
        Navigator.of(context).pushReplacementNamed('/not-registered');
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Hidden admin-onboarding mode: ?mode=setup
    if (_isSetupMode) {
      return CreateBuildingScreen(
        onCreated: () {
          // Clear setup mode and go to standard login
          if (mounted) {
            setState(() => _isSetupMode = false);
          }
        },
      );
    }

    return const PhoneAuthScreen();
  }
}
