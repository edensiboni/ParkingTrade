import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class NotRegisteredScreen extends StatelessWidget {
  const NotRegisteredScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    await AuthService().signOut();
    navigator.pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.no_accounts_outlined,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 32),
              const Text(
                'Not Registered',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your phone number is not registered to any apartment. '
                'Please contact your building admin to be added.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _signOut(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
