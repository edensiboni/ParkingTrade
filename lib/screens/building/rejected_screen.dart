import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class RejectedScreen extends StatelessWidget {
  const RejectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access denied'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.block_rounded,
                  size: 44,
                  color: scheme.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Membership not approved',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'The admin for this building declined your request. '
                'If this looks wrong, reach out to them directly — they can '
                're-invite you any time.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await authService.signOut();
                  if (context.mounted) {
                    navigator.pushReplacementNamed('/auth');
                  }
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
