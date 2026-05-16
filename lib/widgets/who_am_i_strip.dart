import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';

/// A compact strip (designed for app bars) that shows a greeting:
/// "Hello &lt;name&gt;, &lt;role&gt;" (localized).
///
/// The name comes from [Profile.displayName], or is resolved by matching the
/// signed-in user's phone against `authorized_apartments.residents`.
///
/// It is safe to use on any screen — if the user isn't signed in or a profile
/// cannot be resolved, it renders nothing.
class WhoAmIStrip extends StatelessWidget implements PreferredSizeWidget {
  final EdgeInsetsGeometry padding;
  final double height;

  const WhoAmIStrip({
    super.key,
    this.padding = const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
    this.height = 34,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  Future<({Profile profile, String? name})?> _load() async {
    final auth = AuthService();
    final profile = await auth.getCurrentProfile();
    if (profile == null) return null;
    final name = await auth.resolveDisplayName(profile);
    return (profile: profile, name: name);
  }

  String _name(String? resolvedName) {
    final n = resolvedName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'home.who_am_i_unknown'.tr();
  }

  String _role(Profile profile) {
    if (profile.isAdmin) return 'home.role_admin'.tr();
    return 'home.role_tenant'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({Profile profile, String? name})?>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final profile = data.profile;

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        return Padding(
          padding: padding,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'home.who_am_i'.tr(namedArgs: {
                        'name': _name(data.name),
                        'role': _role(profile),
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

