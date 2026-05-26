import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/dev_auth_config.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import 'dev_auth_screen.dart';
import 'phone_auth_screen.dart';

bool isPkceVerifierError(Object error) {
  if (error is AuthException) {
    return error.message.toLowerCase().contains('code verifier');
  }
  return error.toString().toLowerCase().contains('code verifier');
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  bool _isLoading = true;
  bool _navigating = false;
  bool _hasNavigated = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('--- AuthWrapper: initState ---');

    _authSubscription = _authService.authStateChanges.listen(
      (state) {
        debugPrint('--- AuthWrapper: authStateChange event=${state.event} ---');
        _handleAuthChange(state).catchError((error) {
          debugPrint('--- AuthWrapper: error handling auth change: $error ---');
          if (isPkceVerifierError(error)) {
            debugPrint('--- AuthWrapper: PKCE verifier error in handler, clearing session ---');
            _clearSessionAndGoToAuth();
          } else {
            if (mounted) setState(() => _isLoading = false);
          }
        });
      },
      onError: (error) {
        debugPrint('--- AuthWrapper: auth stream error: $error ---');
        if (isPkceVerifierError(error)) {
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

  Future<void> _clearSessionAndGoToAuth() async {
    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('--- AuthWrapper: sign-out during PKCE recovery failed (expected): $e ---');
    }
    _hasNavigated = false;
    _navigating = false;
    if (mounted) {
      setState(() => _isLoading = false);
      context.go('/auth');
    }
  }

  Future<void> _handleAuthChange(AuthState state) async {
    debugPrint('--- AuthWrapper: _handleAuthChange event=${state.event} hasNavigated=$_hasNavigated navigating=$_navigating ---');

    if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.tokenRefreshed) {
      if (_authService.currentSession != null) {
        if (_hasNavigated &&
            (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.tokenRefreshed)) {
          debugPrint('--- AuthWrapper: ${state.event} after imperative navigation, skipping ---');
          return;
        }
        await _navigateBasedOnProfile();
      } else if (state.event == AuthChangeEvent.initialSession) {
        debugPrint('--- AuthWrapper: initialSession with no session, showing auth ---');
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (state.event == AuthChangeEvent.signedOut) {
      debugPrint('--- AuthWrapper: signed out, routing to /auth ---');
      _hasNavigated = false;
      if (mounted) {
        context.go('/auth');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateBasedOnProfile() async {
    debugPrint('--- AuthWrapper: _navigateBasedOnProfile triggered, navigating=$_navigating hasNavigated=$_hasNavigated ---');

    if (_navigating) {
      debugPrint('--- AuthWrapper: already navigating, skipping ---');
      return;
    }
    _navigating = true;
    _hasNavigated = true;

    try {
      debugPrint('--- AuthWrapper: fetching profile... ---');
      final profile = await _authService.getCurrentProfile();
      debugPrint('--- AuthWrapper: profile fetched: $profile ---');

      if (!mounted) {
        debugPrint('--- AuthWrapper: widget unmounted after profile fetch, aborting ---');
        return;
      }

      if (profile == null || profile.apartmentId == null) {
        if (profile != null && profile.isAdmin) {
          debugPrint('--- AuthWrapper: navigating to /admin-dashboard (admin, no apartment) ---');
          context.go('/admin-dashboard');
        } else {
          debugPrint('--- AuthWrapper: navigating to /not-registered ---');
          context.go('/not-registered');
        }
        return;
      }

      if (profile.isAdmin) {
        debugPrint('--- AuthWrapper: navigating to /admin-dashboard ---');
        context.go('/admin-dashboard');
      } else if (profile.status == ProfileStatus.pending) {
        debugPrint('--- AuthWrapper: navigating to /pending-approval ---');
        context.go('/pending-approval');
      } else if (profile.status == ProfileStatus.rejected) {
        debugPrint('--- AuthWrapper: navigating to /rejected ---');
        context.go('/rejected');
      } else {
        debugPrint('--- AuthWrapper: navigating to /home ---');
        context.go('/home');
      }
    } catch (e) {
      debugPrint('--- AuthWrapper: error in _navigateBasedOnProfile: $e ---');
      if (!mounted) return;
      final user = _authService.currentUser;
      if (user == null) {
        _hasNavigated = false;
        context.go('/auth');
      } else {
        context.go('/not-registered');
      }
    } finally {
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
