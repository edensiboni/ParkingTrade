import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import '../../services/parking_spot_service.dart';
import '../../models/parking_spot.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';

class AvailableSpotsScreen extends StatefulWidget {
  final VoidCallback? onBookingCreated;

  const AvailableSpotsScreen({super.key, this.onBookingCreated});

  @override
  State<AvailableSpotsScreen> createState() => _AvailableSpotsScreenState();
}

class _AvailableSpotsScreenState extends State<AvailableSpotsScreen> {
  final _bookingService = BookingService();
  final _spotService = ParkingSpotService();
  List<ParkingSpot> _spots = [];
  /// Maps spotId → the earliest end time of an active (currently-live) availability
  /// period, so we can show "Available until HH:mm" on the card.
  final Map<String, DateTime> _activeUntil = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final spots = await _bookingService.getAvailableSpots();
      if (!mounted) return;

      // For each spot fetch its active (currently-live) availability periods
      // so we can display the earliest end time on the card.
      final activeUntil = <String, DateTime>{};
      final now = DateTime.now();
      for (final spot in spots) {
        try {
          final periods = await _spotService.getAvailabilityPeriods(spot.id);
          // Find any non-recurring period that is currently active
          DateTime? earliest;
          for (final p in periods) {
            if (!p.isRecurring &&
                p.startTime.isBefore(now) &&
                p.endTime.isAfter(now)) {
              if (earliest == null || p.endTime.isBefore(earliest)) {
                earliest = p.endTime;
              }
            }
          }
          if (earliest != null) {
            activeUntil[spot.id] = earliest;
          }
        } catch (_) {
          // Non-fatal: just skip end-time display for this spot.
        }
      }

      setState(() {
        _spots = spots;
        _activeUntil
          ..clear()
          ..addAll(activeUntil);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _showBookingDialog(ParkingSpot spot) async {
    final slots = await _spotService.getAvailableTimeSlots(spotId: spot.id);

    if (!mounted) return;

    if (slots.isEmpty) {
      _showQuickBookDialog(spot);
      return;
    }

    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'bookings.available.pick_time'.tr(),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  'bookings.available.spot_label'.tr(namedArgs: {'id': spot.spotIdentifier}),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final start = slot['start']!;
                      final end = slot['end']!;
                      final fmt = DateFormat('EEE MMM d • h:mm a');
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            foregroundColor: theme.colorScheme.primary,
                            child: const Icon(Icons.schedule_rounded),
                          ),
                          title: Text(fmt.format(start.toLocal())),
                          subtitle: Text(
                            'bookings.available.until'.tr(namedArgs: {'time': fmt.format(end.toLocal())}),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showTimePickerForSlot(spot, start, end);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showTimePickerForSlot(
    ParkingSpot spot,
    DateTime slotStart,
    DateTime slotEnd,
  ) async {
    DateTime selectedStart = slotStart.toLocal();
    DateTime selectedEnd = slotEnd.toLocal();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fmt = DateFormat('EEE MMM d • h:mm a');
          return AlertDialog(
            title: Text('bookings.available.book_spot_title'.tr(namedArgs: {'id': spot.spotIdentifier})),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'bookings.available.within_window'.tr(namedArgs: {
                    'start': fmt.format(slotStart.toLocal()),
                    'end': fmt.format(slotEnd.toLocal()),
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _TimeField(
                  icon: Icons.play_arrow_rounded,
                  label: 'bookings.available.starts'.tr(),
                  value: fmt.format(selectedStart),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedStart,
                      firstDate: slotStart.toLocal(),
                      lastDate: slotEnd.toLocal(),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedStart),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      selectedStart = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute);
                    });
                  },
                ),
                const SizedBox(height: 8),
                _TimeField(
                  icon: Icons.stop_rounded,
                  label: 'bookings.available.ends'.tr(),
                  value: fmt.format(selectedEnd),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedEnd,
                      firstDate: selectedStart,
                      lastDate: slotEnd.toLocal(),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedEnd),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      selectedEnd = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute);
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('bookings.available.cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('bookings.available.send_request'.tr()),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _bookingService.createBookingRequest(
        spotId: spot.id,
        startTime: selectedStart,
        endTime: selectedEnd,
      );
      if (mounted) {
        AppSnack.success(context, 'bookings.available.request_sent'.tr());
        widget.onBookingCreated?.call();
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(
            context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _showQuickBookDialog(ParkingSpot spot) async {
    DateTime? startTime;
    DateTime? endTime;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fmt = DateFormat('EEE MMM d • h:mm a');
          return AlertDialog(
            title: Text('bookings.available.book_spot_title'.tr(namedArgs: {'id': spot.spotIdentifier})),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'bookings.available.always_available'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _TimeField(
                  icon: Icons.play_arrow_rounded,
                  label: 'bookings.available.starts'.tr(),
                  value: startTime == null ? null : fmt.format(startTime!),
                  placeholder: 'bookings.available.select_start'.tr(),
                  onTap: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      startTime = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute);
                    });
                  },
                ),
                const SizedBox(height: 8),
                _TimeField(
                  icon: Icons.stop_rounded,
                  label: 'bookings.available.ends'.tr(),
                  value: endTime == null ? null : fmt.format(endTime!),
                  placeholder: 'bookings.available.select_end'.tr(),
                  onTap: () async {
                    final initial = startTime ?? DateTime.now();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: initial,
                      lastDate: initial.add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                          initial.add(const Duration(hours: 1))),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      endTime = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute);
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('bookings.available.cancel'.tr()),
              ),
              FilledButton(
                onPressed: startTime != null && endTime != null
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text('bookings.available.send_request'.tr()),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || startTime == null || endTime == null || !mounted) {
      return;
    }

    try {
      await _bookingService.createBookingRequest(
        spotId: spot.id,
        startTime: startTime!,
        endTime: endTime!,
      );
      if (mounted) {
        AppSnack.success(context, 'bookings.available.request_sent'.tr());
        widget.onBookingCreated?.call();
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(
            context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonList(count: 4);
    }

    if (_errorMessage != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'bookings.available.load_error_title'.tr(),
        message: _errorMessage,
        action: FilledButton.icon(
          onPressed: _loadSpots,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('bookings.available.try_again'.tr()),
        ),
      );
    }

    if (_spots.isEmpty) {
      return EmptyState(
        icon: Icons.local_parking_rounded,
        title: 'bookings.available.no_spots_title'.tr(),
        message: 'bookings.available.no_spots_message'.tr(),
        action: FilledButton.icon(
          onPressed: _loadSpots,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('bookings.available.refresh'.tr()),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSpots,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _spots.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final spot = _spots[index];
          return _AvailableSpotCard(
            spot: spot,
            activeUntil: _activeUntil[spot.id],
            onTap: () => _showBookingDialog(spot),
          );
        },
      ),
    );
  }
}

class _AvailableSpotCard extends StatelessWidget {
  final ParkingSpot spot;
  final DateTime? activeUntil;
  final VoidCallback onTap;

  const _AvailableSpotCard({
    required this.spot,
    required this.onTap,
    this.activeUntil,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timeFmt = DateFormat('HH:mm');
    final hasEndTime = activeUntil != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.local_parking_rounded,
                    color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'bookings.available.spot_label'
                          .tr(namedArgs: {'id': spot.spotIdentifier}),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    if (hasEndTime)
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'spots.availability.available_until'.tr(namedArgs: {
                              'time': timeFmt.format(activeUntil!),
                            }),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'bookings.available.tap_to_view'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback onTap;

  const _TimeField({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? placeholder ?? '—',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_calendar_outlined,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
