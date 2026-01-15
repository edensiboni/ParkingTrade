import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../models/profile.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final profile = await _authService.getCurrentProfile();
    if (profile != null) {
      if (profile.status == ProfileStatus.approved) {
        // Navigate to main app
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Approval'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.pending_actions,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Your request is pending approval',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Please wait while the building administrator reviews your request.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _checkStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Status'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await _authService.signOut();
                  if (mounted) {
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

