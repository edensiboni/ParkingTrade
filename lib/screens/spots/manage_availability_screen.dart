import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/parking_spot_service.dart';
import '../../models/parking_spot.dart';
import '../../models/spot_availability_period.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';

class ManageAvailabilityScreen extends StatefulWidget {
  final ParkingSpot spot;

  const ManageAvailabilityScreen({
    super.key,
    required this.spot,
  });

  @override
  State<ManageAvailabilityScreen> createState() => _ManageAvailabilityScreenState();
}

class _ManageAvailabilityScreenState extends State<ManageAvailabilityScreen> {
  final _spotService = ParkingSpotService();
  List<SpotAvailabilityPeriod> _periods = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final periods = await _spotService.getAvailabilityPeriods(widget.spot.id);
      setState(() {
        _periods = periods;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        AppSnack.error(context, 'Could not load periods: $e');
      }
    }
  }

  Future<void> _addAvailabilityPeriod() async {
    final now = DateTime.now();
    
    // Pick start date
    final startDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (startDate == null || !mounted) return;

    // Pick start time
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (startTime == null || !mounted) return;

    final startDateTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      startTime.hour,
      startTime.minute,
    );

    // Pick end date
    final endDate = await showDatePicker(
      context: context,
      initialDate: startDateTime,
      firstDate: startDateTime,
      lastDate: startDateTime.add(const Duration(days: 365)),
    );
    if (endDate == null || !mounted) return;

    // Pick end time
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(startDateTime.add(const Duration(hours: 1))),
    );
    if (endTime == null || !mounted) return;

    final endDateTime = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      endTime.hour,
      endTime.minute,
    );

    if (!endDateTime.isAfter(startDateTime)) {
      if (!mounted) return;
      AppSnack.error(context, 'End time must be after start time');
      return;
    }

    try {
      // Debug: Print what we're about to save
      debugPrint('📅 Creating availability period:');
      debugPrint('   Local time: ${startDateTime.toLocal()} to ${endDateTime.toLocal()}');
      debugPrint('   UTC time: ${startDateTime.toUtc()} to ${endDateTime.toUtc()}');
      debugPrint('   ISO string: ${startDateTime.toIso8601String()} to ${endDateTime.toIso8601String()}');
      
      await _spotService.addAvailabilityPeriod(
        spotId: widget.spot.id,
        startTime: startDateTime,
        endTime: endDateTime,
      );
      _loadPeriods();
      if (mounted) {
        AppSnack.success(context, 'Availability added');
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'Could not add availability: $e');
      }
    }
  }

  Future<void> _showAddSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('One-time availability'),
                  subtitle: const Text('Open this spot for a specific window'),
                  onTap: () => Navigator.of(context).pop('once'),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat_rounded),
                  title: const Text('Weekly recurring'),
                  subtitle: const Text('Same days and hours every week'),
                  onTap: () => Navigator.of(context).pop('weekly'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'once') {
      await _addAvailabilityPeriod();
    } else if (choice == 'weekly') {
      await _addRecurringPeriod();
    }
  }

  Future<void> _addRecurringPeriod() async {
    // Pick start date (first occurrence anchor).
    final now = DateTime.now();
    final startDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (startDate == null || !mounted) return;

    // Pick start time-of-day.
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (startTime == null || !mounted) return;

    // Pick end time-of-day.
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (startTime.hour + 1) % 24,
        minute: startTime.minute,
      ),
    );
    if (endTime == null || !mounted) return;

    // Pick weekdays.
    final days = await _pickWeekdays(startDate.weekday);
    if (!mounted || days == null || days.isEmpty) return;

    // Pick an optional "repeat until" end date.
    final untilResult = await _pickRepeatUntil(startDate);
    if (!mounted || untilResult.isCancelled) return;

    // Build start/end DateTimes on the anchor date.
    final anchor = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      startTime.hour,
      startTime.minute,
    );
    var endAnchor = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      endTime.hour,
      endTime.minute,
    );
    if (!endAnchor.isAfter(anchor)) {
      // Treat as same-day window that wraps — bump end to next day.
      endAnchor = endAnchor.add(const Duration(days: 1));
    }

    final untilDate = untilResult.date;
    final pattern = jsonEncode({
      'type': 'weekly',
      'days': days.toList()..sort(),
      // Expansion reads `until` as UTC — store end-of-day so the last day is
      // inclusive. Forever is encoded by omitting the key.
      if (untilDate != null)
        'until': DateTime.utc(
          untilDate.year,
          untilDate.month,
          untilDate.day,
          23,
          59,
        ).toIso8601String(),
    });

    try {
      await _spotService.addAvailabilityPeriod(
        spotId: widget.spot.id,
        startTime: anchor,
        endTime: endAnchor,
        isRecurring: true,
        recurringPattern: pattern,
      );
      _loadPeriods();
      if (mounted) {
        AppSnack.success(context, 'Recurring availability added');
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'Could not add availability: $e');
      }
    }
  }

  Future<Set<String>?> _pickWeekdays(int defaultWeekday) async {
    const labels = <String, String>{
      'MON': 'Mon',
      'TUE': 'Tue',
      'WED': 'Wed',
      'THU': 'Thu',
      'FRI': 'Fri',
      'SAT': 'Sat',
      'SUN': 'Sun',
    };
    const weekdayToCode = <int, String>{
      DateTime.monday: 'MON',
      DateTime.tuesday: 'TUE',
      DateTime.wednesday: 'WED',
      DateTime.thursday: 'THU',
      DateTime.friday: 'FRI',
      DateTime.saturday: 'SAT',
      DateTime.sunday: 'SUN',
    };

    final selected = <String>{weekdayToCode[defaultWeekday] ?? 'MON'};

    return showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Repeat on'),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: labels.entries.map((entry) {
                final isSelected = selected.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  onSelected: (v) {
                    setStateDialog(() {
                      if (v) {
                        selected.add(entry.key);
                      } else {
                        selected.remove(entry.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(selected),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Ask the user how long the recurrence should last. Three outcomes:
  ///   - `_UntilResult.cancelled` — caller should abort;
  ///   - `_UntilResult.forever` — recurs indefinitely (no `until` key written);
  ///   - `_UntilResult.date(d)` — stop repeating after `d`.
  Future<_UntilResult> _pickRepeatUntil(DateTime anchor) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Repeat until',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.all_inclusive_rounded),
                  title: const Text('Forever'),
                  subtitle: const Text('Keeps repeating until you remove it'),
                  onTap: () => Navigator.of(context).pop('forever'),
                ),
                ListTile(
                  leading: const Icon(Icons.event_busy_rounded),
                  title: const Text('Pick an end date'),
                  subtitle: const Text('Stop repeating after this date'),
                  onTap: () => Navigator.of(context).pop('date'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return const _UntilResult.cancelled();
    if (choice == 'forever') return const _UntilResult.forever();

    if (!mounted) return const _UntilResult.cancelled();
    final picked = await showDatePicker(
      context: context,
      initialDate: anchor.add(const Duration(days: 30)),
      firstDate: anchor,
      lastDate: anchor.add(const Duration(days: 365 * 2)),
      helpText: 'Repeat until',
    );
    if (picked == null) return const _UntilResult.cancelled();
    return _UntilResult.date(picked);
  }

  String _describeRecurrence(SpotAvailabilityPeriod period) {
    if (!period.isRecurring) return '';
    final raw = period.recurringPattern ?? '';
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final type = decoded['type']?.toString() ?? 'weekly';

          // Optional "until" suffix shown as "until Apr 30".
          String untilSuffix = '';
          final untilRaw = decoded['until'];
          if (untilRaw is String && untilRaw.isNotEmpty) {
            final untilDate = DateTime.tryParse(untilRaw)?.toLocal();
            if (untilDate != null) {
              untilSuffix = ' · until ${DateFormat('MMM d').format(untilDate)}';
            }
          }

          if (type == 'weekly') {
            final daysRaw = decoded['days'];
            if (daysRaw is List && daysRaw.isNotEmpty) {
              const labels = <String, String>{
                'MON': 'Mon',
                'TUE': 'Tue',
                'WED': 'Wed',
                'THU': 'Thu',
                'FRI': 'Fri',
                'SAT': 'Sat',
                'SUN': 'Sun',
              };
              final days = daysRaw
                  .map((d) => labels[d.toString().toUpperCase()] ?? d.toString())
                  .join(', ');
              return 'Weekly · $days$untilSuffix';
            }
            return 'Weekly$untilSuffix';
          }
          return 'Repeats: $type$untilSuffix';
        }
      } catch (_) {
        // Fall through to raw pattern.
      }
    }
    return 'Repeats: $raw';
  }

  Future<void> _deletePeriod(SpotAvailabilityPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this window?'),
        content: const Text(
            'Future bookings inside this window will no longer be possible. '
            'Existing approved bookings aren\'t affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _spotService.deleteAvailabilityPeriod(period.id);
      _loadPeriods();
      if (mounted) {
        AppSnack.success(context, 'Window removed');
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'Could not remove: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Spot ${widget.spot.spotIdentifier}'),
      ),
      body: _isLoading
          ? const SkeletonList(count: 4)
          : RefreshIndicator(
              onRefresh: _loadPeriods,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'When is this spot free?',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _periods.isEmpty
                              ? 'No windows yet — your spot is open for booking any time it\'s active.'
                              : 'Neighbors can only request times that fall inside the windows below.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_periods.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.event_available_rounded,
                        title: 'No windows set',
                        message:
                            'Add a window to restrict when neighbors can book this spot.',
                      ),
                    )
                  else
                    ..._periods.map((period) {
                      final title = period.isRecurring
                          ? '${DateFormat('HH:mm').format(period.startTime)} – ${DateFormat('HH:mm').format(period.endTime)}'
                          : '${DateFormat('MMM d, y · HH:mm').format(period.startTime)}  →  ${DateFormat('MMM d, y · HH:mm').format(period.endTime)}';
                      final recurrence = _describeRecurrence(period);
                      final durationLabel =
                          _formatDuration(period.startTime, period.endTime);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    period.isRecurring
                                        ? Icons.event_repeat_rounded
                                        : Icons.schedule_rounded,
                                    color: scheme.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(title,
                                          style: theme.textTheme.titleMedium),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (recurrence.isNotEmpty)
                                            StatusChip(
                                              label: recurrence,
                                              tone: StatusTone.info,
                                              icon: Icons.event_repeat_rounded,
                                            )
                                          else
                                            const StatusChip(
                                              label: 'One-time',
                                              tone: StatusTone.neutral,
                                              icon: Icons.event_rounded,
                                            ),
                                          StatusChip(
                                            label: durationLabel,
                                            tone: StatusTone.neutral,
                                            icon: Icons.timelapse_rounded,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove window',
                                  icon: Icon(Icons.delete_outline_rounded,
                                      color: scheme.error),
                                  onPressed: () => _deletePeriod(period),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add window'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  String _formatDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}';
    } else {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    }
  }
}

/// Tri-state return from the "repeat until" picker. Using an explicit type
/// instead of `DateTime?` lets us distinguish user-cancelled from "forever"
/// without overloading `null`.
class _UntilResult {
  final bool isCancelled;
  final bool isForever;
  final DateTime? date;

  const _UntilResult._(
      {required this.isCancelled,
      required this.isForever,
      required this.date});

  const _UntilResult.cancelled()
      : this._(isCancelled: true, isForever: false, date: null);
  const _UntilResult.forever()
      : this._(isCancelled: false, isForever: true, date: null);
  const _UntilResult.date(DateTime d)
      : this._(isCancelled: false, isForever: false, date: d);
}
