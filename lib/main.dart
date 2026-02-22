import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'firebase_initializer_stub.dart' if (dart.library.io) 'firebase_initializer.dart' as firebase_init;
import 'services/auth_service.dart';
import 'services/notification_service_stub.dart' if (dart.library.io) 'services/notification_service.dart';
import 'screens/auth/phone_auth_screen.dart';
import 'screens/building/join_building_screen.dart';
import 'screens/building/pending_approval_screen.dart';
import 'screens/spots/parking_spots_screen.dart';
import 'models/profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final supabaseUrl = SupabaseConfig.supabaseUrl;
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
  );

  // Initialize notification service only on mobile (not supported on web)
  if (!kIsWeb) {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
    } catch (e) {
      debugPrint('Warning: Notification service initialization failed: $e');
    }
  }

  runApp(const ParkingTradeApp());
}

class ParkingTradeApp extends StatelessWidget {
  const ParkingTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parking Trade',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
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
        // Use pushNamedAndRemoveUntil to clear navigation stack
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

      // New user or no profile - go to join building
      if (profile == null) {
        Navigator.of(context).pushReplacementNamed('/join-building');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // User has profile - navigate based on status
      if (profile.buildingId == null) {
        Navigator.of(context).pushReplacementNamed('/join-building');
      } else if (profile.status == ProfileStatus.pending) {
        Navigator.of(context).pushReplacementNamed('/pending-approval');
      } else if (profile.status == ProfileStatus.approved) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/join-building');
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error navigating based on profile: $e');
      // Only navigate back to auth if there's a real error (not just missing profile)
      // Check if user is still authenticated
      final user = _authService.currentUser;
      if (user == null) {
        // User is not authenticated, go to auth
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/auth');
        }
      } else {
        // User is authenticated but profile fetch failed - try join building
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/join-building');
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
