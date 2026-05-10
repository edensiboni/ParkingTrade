import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Result returned by [showAddAvailabilityDurationSheet].
///
/// [startTime] is always `DateTime.now()` at the moment the sheet resolves.
/// [endTime] is the user-chosen end time in local time; callers should convert
/// to UTC before persisting.
class AvailabilityDuration {
  final DateTime startTime;
  final DateTime endTime;

  const AvailabilityDuration({required this.startTime, required this.endTime});
}

/// Shows a [ModalBottomSheet] that lets the tenant quickly specify how long
/// their parking spot will be free.
///
/// Returns an [AvailabilityDuration] with `start = now` and the resolved
/// `endTime`, or `null` if the user cancelled.
Future<AvailabilityDuration?> showAddAvailabilityDurationSheet(
    BuildContext context) {
  return showModalBottomSheet<AvailabilityDuration>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const _DurationSheet(),
  );
}

class _DurationSheet extends StatelessWidget {
  const _DurationSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final timeFmt = DateFormat('HH:mm');

    // End of today at 23:59
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Text(
              'spots.availability.add_duration_title'.tr(),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'spots.availability.add_duration_subtitle'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // ── Quick-select chips ───────────────────────────────────────────
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _QuickChip(
                  label: 'spots.availability.quick_1h'.tr(),
                  sublabel: timeFmt.format(now.add(const Duration(hours: 1))),
                  onTap: () => Navigator.of(context).pop(
                    AvailabilityDuration(
                      startTime: now,
                      endTime: now.add(const Duration(hours: 1)),
                    ),
                  ),
                ),
                _QuickChip(
                  label: 'spots.availability.quick_2h'.tr(),
                  sublabel: timeFmt.format(now.add(const Duration(hours: 2))),
                  onTap: () => Navigator.of(context).pop(
                    AvailabilityDuration(
                      startTime: now,
                      endTime: now.add(const Duration(hours: 2)),
                    ),
                  ),
                ),
                _QuickChip(
                  label: 'spots.availability.quick_4h'.tr(),
                  sublabel: timeFmt.format(now.add(const Duration(hours: 4))),
                  onTap: () => Navigator.of(context).pop(
                    AvailabilityDuration(
                      startTime: now,
                      endTime: now.add(const Duration(hours: 4)),
                    ),
                  ),
                ),
                // "Until end of day" only shown if EOD is in the future
                if (endOfDay.isAfter(now))
                  _QuickChip(
                    label: 'spots.availability.quick_eod'.tr(),
                    sublabel: timeFmt.format(endOfDay),
                    onTap: () => Navigator.of(context).pop(
                      AvailabilityDuration(
                        startTime: now,
                        endTime: endOfDay,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 8),

            // ── Custom time button ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time_rounded),
                label: Text('spots.availability.custom_time'.tr()),
                onPressed: () async {
                  final result = await _pickCustomTime(context, now);
                  if (result != null && context.mounted) {
                    Navigator.of(context).pop(result);
                  }
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<AvailabilityDuration?> _pickCustomTime(
      BuildContext context, DateTime now) async {
    final timeFmt = DateFormat('HH:mm');

    // Default suggestion: now + 2h, clamped to 23:00.
    final suggestionHour = (now.hour + 2).clamp(0, 23);

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: suggestionHour, minute: 0),
      helpText: 'spots.availability.custom_time_title'.tr(),
    );

    if (picked == null || !context.mounted) return null;

    // Build a candidate end time on today
    var end = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);

    // If the picked time is already in the past, advance to tomorrow
    final isTomorrow = !end.isAfter(now);
    if (isTomorrow) {
      end = end.add(const Duration(days: 1));
      // Inform the user with a brief SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${'spots.availability.free_until'.tr(namedArgs: {'time': timeFmt.format(end)})} ${'spots.availability.tomorrow_note'.tr()}',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return AvailabilityDuration(startTime: now, endTime: end);
  }
}

/// A styled chip for the quick-select row.
class _QuickChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
