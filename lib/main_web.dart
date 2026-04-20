// Web entry point. Optional Firebase web config enables browser push (FCM).
// Use: flutter run -d chrome -t lib/main_web.dart
//      flutter build web -t lib/main_web.dart

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/firebase_options_web.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/notification_service_web.dart';
import 'screens/auth/phone_auth_screen.dart';
import 'screens/building/join_building_screen.dart';
import 'screens/building/pending_approval_screen.dart';
import 'screens/spots/parking_spots_screen.dart';
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
        '/join-building': (context) => const JoinBuildingScreen(),
        '/pending-approval': (context) => const PendingApprovalScreen(),
        '/home': (context) => const ParkingSpotsScreen(),
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
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

  Future<void> _checkAuth() async {
    final user = _authService.currentUser;
    if (user != null) {
      await _navigateBasedOnProfile();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAuthChange(AuthState state) async {
    if (state.event == AuthChangeEvent.signedIn) {
      await _navigateBasedOnProfile();
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

      if (profile == null) {
        Navigator.of(context).pushReplacementNamed('/join-building');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (profile.buildingId == null) {
        Navigator.of(context).pushReplacementNamed('/join-building');
      } else if (profile.status == ProfileStatus.pending) {
        Navigator.of(context).pushReplacementNamed('/pending-approval');
      } else if (profile.status == ProfileStatus.approved) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/join-building');
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error navigating based on profile: $e');
      final user = _authService.currentUser;
      if (user == null && mounted) {
        Navigator.of(context).pushReplacementNamed('/auth');
      } else if (mounted) {
        Navigator.of(context).pushReplacementNamed('/join-building');
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
    return const PhoneAuthScreen();
  }
}
