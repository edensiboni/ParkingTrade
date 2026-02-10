// Web entry point. Optional Firebase web config enables browser push (FCM).
// Use: flutter run -d chrome -t lib/main_web.dart
//      flutter build web -t lib/main_web.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/firebase_options_web.dart';
import 'config/supabase_config.dart';
import 'services/auth_service.dart';
import 'services/notification_service_web.dart';
import 'screens/auth/phone_auth_screen.dart';
import 'screens/building/join_building_screen.dart';
import 'screens/building/pending_approval_screen.dart';
import 'screens/spots/parking_spots_screen.dart';
import 'models/profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('### MAIN STARTED (web) ###');

  if (!SupabaseConfig.isConfigured) {
    throw Exception(
      'Supabase configuration is missing. Please set SUPABASE_URL and SUPABASE_ANON_KEY (e.g. via --dart-define).',
    );
  }

  final supabaseUrl = SupabaseConfig.supabaseUrl;
  final supabaseAnonKey = SupabaseConfig.supabaseAnonKey;
  debugPrint('Supabase URL = $supabaseUrl');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  if (FirebaseOptionsWeb.isConfigured) {
    try {
      await Firebase.initializeApp(options: FirebaseOptionsWeb.options);
      await WebNotificationService().initialize();
    } catch (e) {
      debugPrint('Firebase/Web push init failed: $e');
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

  @override
  void initState() {
    super.initState();
    _checkAuth();
    _authService.authStateChanges.listen((state) {
      _handleAuthChange(state);
    });
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
