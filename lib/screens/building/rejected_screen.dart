import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class RejectedScreen extends StatelessWidget {
  const RejectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Denied'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.block,
                size: 80,
                color: Colors.red[300],
              ),
              const SizedBox(height: 24),
              const Text(
                'Membership Rejected',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your request to join this building was not approved. '
                'Please contact the building administrator if you believe this is an error.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await authService.signOut();
                  if (context.mounted) {
                    navigator.pushReplacementNamed('/auth');
                  }
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
