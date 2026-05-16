import 'package:flutter/material.dart';
import '../../config/dev_auth_config.dart';
import '../../services/auth_service.dart';

/// Dev/test-only auth screen that lets you sign in as constant users
/// using email/password (bypasses OTP).
///
/// Enable with `--dart-define=DEV_AUTH_ENABLED=true`.
class DevAuthScreen extends StatefulWidget {
  const DevAuthScreen({super.key});

  @override
  State<DevAuthScreen> createState() => _DevAuthScreenState();
}

class _DevAuthScreenState extends State<DevAuthScreen> {
  final _authService = AuthService();
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _signInAs(DevAuthUser user) async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithEmailPassword(
        email: user.email,
        password: user.password,
      );
      // Navigation is handled by auth listener in main flow.
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSigningIn = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = DevAuthConfig.users;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dev Sign In'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _isSigningIn ? null : _signOut,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: users.isEmpty
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Dev auth is enabled, but no users are configured.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Set environment variables, for example:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'DEV_AUTH_USER_A_EMAIL / DEV_AUTH_USER_A_PASSWORD (and B/C)',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Icon(Icons.warning_amber_rounded, size: 56),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Sign in as a test user (OTP bypass).',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ...users.map(
                    (u) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: ElevatedButton.icon(
                        onPressed: _isSigningIn ? null : () => _signInAs(u),
                        icon: const Icon(Icons.person),
                        label: Text('Sign in as User ${u.label}'),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
