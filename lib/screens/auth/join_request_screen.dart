import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/join_request_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snack.dart';

/// Resident-facing "ask to join a building" form. Reached from
/// [NotRegisteredScreen] when the signed-in user's phone isn't pre-authorised
/// for any building. Submits through [JoinRequestService.submit].
class JoinRequestScreen extends StatefulWidget {
  const JoinRequestScreen({super.key});

  @override
  State<JoinRequestScreen> createState() => _JoinRequestScreenState();
}

class _JoinRequestScreenState extends State<JoinRequestScreen> {
  final _service = JoinRequestService();
  final _formKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();
  final _unitController = TextEditingController();
  final _nameController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Prefill the name from the auth identity when we have one.
    final user = Supabase.instance.client.auth.currentUser;
    final metaName = (user?.userMetadata?['full_name'] as String?)?.trim();
    if (metaName != null && metaName.isNotEmpty) {
      _nameController.text = metaName;
    }
  }

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _unitController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final result = await _service.submit(
        inviteCode: _inviteCodeController.text,
        apartmentIdentifier: _unitController.text,
        displayName: _nameController.text,
      );
      if (!mounted) return;

      switch (result.outcome) {
        case JoinRequestOutcome.linked:
        case JoinRequestOutcome.alreadyMember:
          AppSnack.success(context, 'auth.join_request.linked'.tr());
          context.go('/');
        case JoinRequestOutcome.pending:
          context.go('/join-request-pending');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('auth.join_request.title'.tr())),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      ),
                      child: Icon(Icons.apartment_rounded,
                          size: 34, color: scheme.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'auth.join_request.heading'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'auth.join_request.subtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'auth.join_request.invite_code_label'.tr(),
                        hintText: 'auth.join_request.invite_code_hint'.tr(),
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'auth.join_request.invite_code_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _unitController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'auth.join_request.unit_label'.tr(),
                        hintText: 'auth.join_request.unit_hint'.tr(),
                        prefixIcon: const Icon(Icons.door_front_door_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'auth.join_request.unit_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'auth.join_request.name_label'.tr(),
                        hintText: 'auth.join_request.name_hint'.tr(),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_submitting
                          ? 'auth.join_request.submitting'.tr()
                          : 'auth.join_request.submit'.tr()),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          _submitting ? null : () => Navigator.of(context).maybePop(),
                      child: Text('auth.join_request.back'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
