import 'package:flutter/material.dart';

enum StatusTone { neutral, info, success, warning, danger }

/// A compact pill that summarizes a state — used for booking/spot statuses.
class StatusChip extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final IconData? icon;

  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  Color _bg(ColorScheme scheme) {
    switch (tone) {
      case StatusTone.success:
        return const Color(0xFFE4F3EA);
      case StatusTone.warning:
        return const Color(0xFFFDF1DA);
      case StatusTone.danger:
        return const Color(0xFFFBE3DF);
      case StatusTone.info:
        return const Color(0xFFE2ECFE);
      case StatusTone.neutral:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _fg(ColorScheme scheme) {
    switch (tone) {
      case StatusTone.success:
        return const Color(0xFF1E6B46);
      case StatusTone.warning:
        return const Color(0xFF8A5A10);
      case StatusTone.danger:
        return const Color(0xFF8B2A1E);
      case StatusTone.info:
        return const Color(0xFF234BB5);
      case StatusTone.neutral:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = _fg(scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _bg(scheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
