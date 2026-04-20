import 'package:flutter/material.dart';

/// Consistent snack-bar helpers with tone-aware styling.
class AppSnack {
  AppSnack._();

  static void success(BuildContext context, String message) =>
      _show(context, message, Icons.check_circle, const Color(0xFF1E6B46));

  static void error(BuildContext context, String message) =>
      _show(context, message, Icons.error_outline, const Color(0xFFC0392B));

  static void info(BuildContext context, String message) =>
      _show(context, message, Icons.info_outline, null);

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color? accent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        backgroundColor: scheme.inverseSurface,
        content: Row(
          children: [
            Icon(icon, size: 20, color: accent ?? scheme.onInverseSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onInverseSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
