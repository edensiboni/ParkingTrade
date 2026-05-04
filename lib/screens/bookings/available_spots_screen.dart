import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import '../../services/parking_spot_service.dart';
import '../../models/parking_spot.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snack.dart';
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

  /// Maps spotId → the earliest end time of an active (currently-live)
  /// availability period, so we can show "Available until HH:mm".
  final Map<String, DateTime> _activeUntil = {};

  /// Maps spotId → all its availability periods (used for time-filter matching).
  final Map<String, List<_PeriodWindow>> _spotWindows = {};

  // ── Time filter state ────────────────────────────────────────────────────
  DateTime? _filterDate;
  TimeOfDay? _filterTime;

  bool get _isFilterActive => _filterDate != null && _filterTime != null;

  DateTime get _filterDateTime {
    final d = _filterDate!;
    final t = _filterTime!;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  List<ParkingSpot> get _filteredSpots {
    if (!_isFilterActive) return _spots;
    final target = _filterDateTime;
    return _spots.where((spot) {
      final windows = _spotWindows[spot.id] ?? [];
      return windows.any(
        (w) =>
            !target.isBefore(w.start) && !target.isAfter(w.end),
      );
    }).toList();
  }

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

      final activeUntil = <String, DateTime>{};
      final spotWindows = <String, List<_PeriodWindow>>{};
      final now = DateTime.now();
      for (final spot in spots) {
        try {
          final periods = await _spotService.getAvailabilityPeriods(spot.id);
          DateTime? earliest;
          final windows = <_PeriodWindow>[];
          for (final p in periods) {
            if (!p.isRecurring && p.endTime.isAfter(now)) {
              // Collect all current/future windows for filter matching
              windows.add(_PeriodWindow(
                start: p.startTime.toLocal(),
                end: p.endTime.toLocal(),
              ));
              // Also determine "active until" for live display
              if (p.startTime.isBefore(now)) {
                if (earliest == null || p.endTime.isBefore(earliest)) {
                  earliest = p.endTime;
                }
              }
            }
          }
          spotWindows[spot.id] = windows;
          if (earliest != null) {
            activeUntil[spot.id] = earliest;
          }
        } catch (_) {
          // Non-fatal: skip end-time display for this spot.
        }
      }

      setState(() {
        _spots = spots;
        _activeUntil
          ..clear()
          ..addAll(activeUntil);
        _spotWindows
          ..clear()
          ..addAll(spotWindows);
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

  // ── Filter pickers ───────────────────────────────────────────────────────

  Future<void> _pickFilterDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null && mounted) {
      setState(() => _filterDate = picked);
    }
  }

  Future<void> _pickFilterTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _filterTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _filterTime = picked);
    }
  }

  void _clearFilter() {
    setState(() {
      _filterDate = null;
      _filterTime = null;
    });
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
                  'bookings.available.spot_label'
                      .tr(namedArgs: {'id': spot.spotIdentifier}),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                            'bookings.available.until'.tr(
                                namedArgs: {'time': fmt.format(end.toLocal())}),
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
            title: Text('bookings.available.book_spot_title'
                .tr(namedArgs: {'id': spot.spotIdentifier})),
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
                      selectedStart = DateTime(date.year, date.month,
                          date.day, time.hour, time.minute);
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
                      selectedEnd = DateTime(date.year, date.month,
                          date.day, time.hour, time.minute);
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
        AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
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
            title: Text('bookings.available.book_spot_title'
                .tr(namedArgs: {'id': spot.spotIdentifier})),
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

    if (confirmed != true ||
        startTime == null ||
        endTime == null ||
        !mounted) return;

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
        AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) { return const SkeletonList(count: 4); }

    if (_errorMessage != null) {
      return _FindParkingEmpty(
        mode: _EmptyMode.error,
        errorMessage: _errorMessage,
        onRefresh: _loadSpots,
      );
    }

    if (_spots.isEmpty) {
      return _FindParkingEmpty(
        mode: _EmptyMode.noSpots,
        onRefresh: _loadSpots,
      );
    }

    final displaySpots = _filteredSpots;

    return RefreshIndicator(
      onRefresh: _loadSpots,
      color: AppTheme.brandIndigo,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _FindParkingHeader(spotCount: _spots.length),
          ),
          // ── Time filter bar ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: _TimeFilterBar(
              filterDate: _filterDate,
              filterTime: _filterTime,
              isFilterActive: _isFilterActive,
              onPickDate: _pickFilterDate,
              onPickTime: _pickFilterTime,
              onClear: _clearFilter,
            ),
          ),
          // ── Results ──────────────────────────────────────────────────
          if (displaySpots.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _FilterEmptyState(onClear: _clearFilter),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: displaySpots.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final spot = displaySpots[index];
                  return _AvailableSpotCard(
                    spot: spot,
                    activeUntil: _activeUntil[spot.id],
                    index: index,
                    onTap: () => _showBookingDialog(spot),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Find Parking Header
// ─────────────────────────────────────────────────────────────────────────────

class _FindParkingHeader extends StatelessWidget {
  final int spotCount;
  const _FindParkingHeader({required this.spotCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'bookings.available.spots_available_now'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'bookings.available.neighbors_sharing'.tr(namedArgs: {'count': '$spotCount'}),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.inkMuted,
            ),
          ),
          const SizedBox(height: 16),
          // Live indicator
          Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: 7),
              Text(
                'bookings.available.live_label'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'bookings.available.pull_to_refresh'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.inkSoft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppTheme.success,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Available Spot Card
// ─────────────────────────────────────────────────────────────────────────────

class _AvailableSpotCard extends StatefulWidget {
  final ParkingSpot spot;
  final DateTime? activeUntil;
  final VoidCallback onTap;
  final int index;

  const _AvailableSpotCard({
    required this.spot,
    required this.onTap,
    required this.index,
    this.activeUntil,
  });

  @override
  State<_AvailableSpotCard> createState() => _AvailableSpotCardState();
}

class _AvailableSpotCardState extends State<_AvailableSpotCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350 + widget.index * 50),
    );
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    // Small stagger delay per card
    Future.delayed(Duration(milliseconds: widget.index * 45), () {
      if (mounted) _entryCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat('HH:mm');
    final hasEndTime = widget.activeUntil != null;

    // Time remaining label
    String? timeRemaining;
    if (hasEndTime) {
      final diff = widget.activeUntil!.difference(DateTime.now());
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      if (hours > 0) {
        timeRemaining = 'bookings.available.time_remaining_hours'
            .tr(namedArgs: {'hours': '$hours', 'mins': '$mins'});
      } else {
        timeRemaining = 'bookings.available.time_remaining_mins'
            .tr(namedArgs: {'mins': '$mins'});
      }
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.hairline),
            boxShadow: [
              BoxShadow(
                color: AppTheme.ink.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Spot number badge
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppTheme.brandIndigo.withValues(alpha: 0.22),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_parking_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(height: 1),
                          Text(
                            widget.spot.spotIdentifier,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'bookings.available.spot_number'.tr(namedArgs: {'number': widget.spot.spotIdentifier}),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (hasEndTime) ...[
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'bookings.available.until'.tr(namedArgs: {'time': timeFmt.format(widget.activeUntil!)}),
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: AppTheme.inkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (timeRemaining != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                timeRemaining,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ] else
                            Text(
                              'bookings.available.tap_to_see_windows'.tr(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Pill Book Now button
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.brandIndigo
                                  .withValues(alpha: 0.28),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          'bookings.available.book_now'.tr(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Friendly Empty State
// ─────────────────────────────────────────────────────────────────────────────

enum _EmptyMode { noSpots, error }

class _FindParkingEmpty extends StatefulWidget {
  final _EmptyMode mode;
  final String? errorMessage;
  final VoidCallback onRefresh;

  const _FindParkingEmpty({
    required this.mode,
    required this.onRefresh,
    this.errorMessage,
  });

  @override
  State<_FindParkingEmpty> createState() => _FindParkingEmptyState();
}

class _FindParkingEmptyState extends State<_FindParkingEmpty>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = widget.mode == _EmptyMode.error;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Floating illustration
              AnimatedBuilder(
                animation: _floatAnim,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, _floatAnim.value),
                  child: child,
                ),
                child: _SleepingCarIllustration(isError: isError),
              ),
              const SizedBox(height: 28),
              Text(
                isError
                    ? 'bookings.available.error_title'.tr()
                    : 'bookings.available.no_spots_now_title'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  isError
                      ? (widget.errorMessage ?? 'bookings.available.pull_to_try_again'.tr())
                      : 'bookings.available.no_spots_now_message'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.inkMuted,
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(isError
                    ? 'bookings.available.try_again'.tr()
                    : 'bookings.available.refresh'.tr()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, 46),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  side: const BorderSide(color: AppTheme.hairline, width: 1.4),
                  foregroundColor: AppTheme.inkMuted,
                  textStyle: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A cute SVG-style sleeping car illustration drawn with CustomPaint.
class _SleepingCarIllustration extends StatelessWidget {
  final bool isError;
  const _SleepingCarIllustration({required this.isError});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFFFEE2E2)
            : AppTheme.brandIndigo.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isError ? Icons.wifi_off_rounded : Icons.directions_car_rounded,
            size: 60,
            color: isError
                ? AppTheme.danger.withValues(alpha: 0.5)
                : AppTheme.brandIndigo.withValues(alpha: 0.35),
          ),
          if (!isError) ...[
            // ZZZ bubbles
            const Positioned(
              top: 22,
              right: 24,
              child: _ZzzBubble(size: 13, delay: 0),
            ),
            const Positioned(
              top: 12,
              right: 16,
              child: _ZzzBubble(size: 10, delay: 300),
            ),
            const Positioned(
              top: 6,
              right: 10,
              child: _ZzzBubble(size: 8, delay: 600),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZzzBubble extends StatefulWidget {
  final double size;
  final int delay;
  const _ZzzBubble({required this.size, required this.delay});

  @override
  State<_ZzzBubble> createState() => _ZzzBubbleState();
}

class _ZzzBubbleState extends State<_ZzzBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _opacity = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1), weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1, end: 1), weight: 60),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1, end: 0), weight: 20),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _slide = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slide.value),
        child: Opacity(
          opacity: _opacity.value,
          child: Text(
            'z',
            style: TextStyle(
              fontSize: widget.size,
              color: AppTheme.brandIndigo.withValues(alpha: 0.6),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple data class for a concrete availability window
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodWindow {
  final DateTime start;
  final DateTime end;
  const _PeriodWindow({required this.start, required this.end});
}

// ─────────────────────────────────────────────────────────────────────────────
// Time Filter Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TimeFilterBar extends StatelessWidget {
  final DateTime? filterDate;
  final TimeOfDay? filterTime;
  final bool isFilterActive;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onClear;

  const _TimeFilterBar({
    required this.filterDate,
    required this.filterTime,
    required this.isFilterActive,
    required this.onPickDate,
    required this.onPickTime,
    required this.onClear,
  });

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'bookings.available.filter_today'.tr();
    if (d == tomorrow) return 'bookings.available.filter_tomorrow'.tr();
    return DateFormat('d MMM').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isFilterActive
            ? AppTheme.brandIndigo.withValues(alpha: 0.06)
            : AppTheme.subtleSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFilterActive
              ? AppTheme.brandIndigo.withValues(alpha: 0.30)
              : AppTheme.hairline,
          width: isFilterActive ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // ── Date picker pill ──────────────────────────────────────────
          Expanded(
            child: _FilterPill(
              icon: Icons.calendar_today_rounded,
              label: filterDate != null
                  ? _dateLabel(filterDate!)
                  : 'bookings.available.filter_select_date'.tr(),
              isSet: filterDate != null,
              onTap: onPickDate,
            ),
          ),
          const SizedBox(width: 8),
          // ── Time picker pill ──────────────────────────────────────────
          Expanded(
            child: _FilterPill(
              icon: Icons.access_time_rounded,
              label: filterTime != null
                  ? filterTime!.format(context)
                  : 'bookings.available.filter_select_time'.tr(),
              isSet: filterTime != null,
              onTap: onPickTime,
            ),
          ),
          // ── Clear button ──────────────────────────────────────────────
          if (isFilterActive) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClear,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded,
                        size: 13, color: AppTheme.danger),
                    const SizedBox(width: 4),
                    Text(
                      'bookings.available.filter_clear'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSet;
  final VoidCallback onTap;

  const _FilterPill({
    required this.icon,
    required this.label,
    required this.isSet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSet ? AppTheme.brandIndigo : AppTheme.inkSoft;
    final bgColor = isSet
        ? AppTheme.brandIndigo.withValues(alpha: 0.10)
        : AppTheme.cardSurface;
    final borderColor = isSet
        ? AppTheme.brandIndigo.withValues(alpha: 0.28)
        : AppTheme.hairline;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: isSet ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter empty state
// ─────────────────────────────────────────────────────────────────────────────

class _FilterEmptyState extends StatelessWidget {
  final VoidCallback onClear;
  const _FilterEmptyState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.brandIndigo.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppTheme.brandIndigo.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'bookings.available.filter_no_results_title'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'bookings.available.filter_no_results_message'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.inkMuted,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
            label: Text('bookings.available.filter_clear'.tr()),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(140, 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              side: BorderSide(
                color: AppTheme.brandIndigo.withValues(alpha: 0.35),
                width: 1.4,
              ),
              foregroundColor: AppTheme.brandIndigo,
              textStyle: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Time Field (reused in booking dialogs)
// ─────────────────────────────────────────────────────────────────────────────

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
