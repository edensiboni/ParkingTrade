import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/building_join_request.dart';
import '../../services/auth_service.dart';
import '../../services/join_request_service.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';

/// Shown while a user's [BuildingJoinRequest] is `pending`, and again on every
/// later sign-in until it is actioned. A `rejected` request shows the admin's
/// reason plus a path back to [JoinRequestScreen]. Approval routes the user
/// into the app via [AuthWrapper] (`/`).
class JoinRequestPendingScreen extends StatefulWidget {
  const JoinRequestPendingScreen({super.key});

  @override
  State<JoinRequestPendingScreen> createState() =>
      _JoinRequestPendingScreenState();
}

class _JoinRequestPendingScreenState extends State<JoinRequestPendingScreen> {
  final _service = JoinRequestService();
  final _auth = AuthService();

  BuildingJoinRequest? _request;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final req = await _service.myLatestRequest();
      if (!mounted) return;

      // Nothing pending/rejected here anymore — let AuthWrapper re-route.
      if (req == null ||
          req.status == JoinRequestStatus.approved ||
          req.status == JoinRequestStatus.cancelled) {
        context.go('/');
        return;
      }
      setState(() {
        _request = req;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _checkAgain() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final profile = await _auth.getCurrentProfile();
      if (!mounted) return;
      if (profile != null) {
        context.go('/');
        return;
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final req = _request;
    if (req == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('auth.join_request_pending.cancel_title'.tr()),
        content: Text('auth.join_request_pending.cancel_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('admin.dialog.cancel'.tr()),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('auth.join_request_pending.cancel_confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.cancel(req.id);
      if (!mounted) return;
      context.go('/not-registered');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final req = _request!;
    final rejected = req.status == JoinRequestStatus.rejected;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buildingLabel =
        req.buildingName ?? 'auth.join_request_pending.your_building'.tr();

    return Scaffold(
      appBar: AppBar(
        title: Text('auth.join_request_pending.title'.tr()),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: EmptyState(
          icon: rejected
              ? Icons.cancel_outlined
              : Icons.hourglass_top_rounded,
          title: rejected
              ? 'auth.join_request_pending.rejected_title'.tr()
              : 'auth.join_request_pending.waiting_title'.tr(),
          message: rejected
              ? (req.reviewReason?.trim().isNotEmpty == true
                  ? tr('auth.join_request_pending.rejected_reason',
                      namedArgs: {'reason': req.reviewReason!.trim()})
                  : 'auth.join_request_pending.rejected_message'.tr())
              : tr('auth.join_request_pending.waiting_message', namedArgs: {
                  'building': buildingLabel,
                  'unit': req.apartmentIdentifier,
                }),
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rejected)
                FilledButton.icon(
                  onPressed: _busy ? null : () => context.go('/join-request'),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('auth.join_request_pending.try_again'.tr()),
                )
              else
                FilledButton.icon(
                  onPressed: _busy ? null : _checkAgain,
                  icon: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label:
                      Text('auth.join_request_pending.check_again'.tr()),
                ),
              const SizedBox(height: 8),
              if (!rejected)
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: Text('auth.join_request_pending.cancel'.tr()),
                ),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: Text('auth.join_request_pending.sign_out'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
