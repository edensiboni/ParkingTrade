import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';

/// A compact strip (designed for app bars) that shows:
/// "Who am I · <name> · <role>"
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

  String _name(Profile? profile) {
    final n = profile?.displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'home.who_am_i_unknown'.tr();
  }

  String _role(Profile? profile) {
    if (profile?.isAdmin == true) return 'home.role_admin'.tr();
    return 'home.role_tenant'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: AuthService().getCurrentProfile(),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile == null) return const SizedBox.shrink();

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
                        'name': _name(profile),
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

