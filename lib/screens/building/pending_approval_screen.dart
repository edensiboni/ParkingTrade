import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../models/profile.dart';
import '../../widgets/empty_state.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _authService = AuthService();
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final profile = await _authService.getCurrentProfile();
      if (!mounted) return;
      if (profile?.status == ProfileStatus.approved) {
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending approval'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: EmptyState(
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting on your building admin',
          message:
              'We\'ve sent your request. You\'ll get access as soon as it\'s approved.',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _checking ? null : _checkStatus,
                icon: _checking
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('Check again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await _authService.signOut();
                  if (mounted) {
                    navigator.pushReplacementNamed('/auth');
                  }
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
