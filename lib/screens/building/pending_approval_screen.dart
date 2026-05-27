import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
        context.go('/home');
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
        title: Text('building.pending_approval.title'.tr()),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: EmptyState(
          icon: Icons.hourglass_top_rounded,
          title: 'building.pending_approval.waiting_title'.tr(),
          message: 'building.pending_approval.waiting_message'.tr(),
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
                label: Text('building.pending_approval.check_again'.tr()),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await _authService.signOut();
                  if (!mounted) return;
                  context.go('/auth');
                },
                child: Text('building.pending_approval.sign_out'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
