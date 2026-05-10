import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class NotRegisteredScreen extends StatelessWidget {
  const NotRegisteredScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    await AuthService().signOut();
    navigator.pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(32, 48, 32, 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon badge ─────────────────────────────────────────────
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    ),
                    child: Icon(
                      Icons.no_accounts_outlined,
                      size: 44,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Title ──────────────────────────────────────────────────
                  Text(
                    'auth.not_registered.title'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Message ────────────────────────────────────────────────
                  Text(
                    'auth.not_registered.message'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // ── Sign out ───────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => _signOut(context),
                      child: Text('auth.not_registered.sign_out'.tr()),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Admin link ─────────────────────────────────────────────
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/setup'),
                    child: Text('auth.not_registered.admin_link'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
