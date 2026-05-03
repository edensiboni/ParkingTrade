import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import '../../services/auth_service.dart';
import '../../models/booking_request.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/status_chip.dart';
import '../chat/chat_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;

  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final _bookingService = BookingService();
  final _authService = AuthService();
  BookingDetails? _details;
  String? _currentApartmentId;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _bookingService.getBookingDetails(widget.bookingId),
        _authService.getCurrentProfile(),
      ]);
      if (!mounted) return;
      setState(() {
        _details = results[0] as BookingDetails?;
        _currentApartmentId =
            (results[1] as dynamic)?.apartmentId as String?;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'bookings.detail.could_not_load'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _approveBooking(bool approve) async {
    if (_details == null) return;
    setState(() => _isProcessing = true);
    try {
      await _bookingService.approveBooking(
        bookingId: _details!.booking.id,
        approve: approve,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) AppSnack.error(context, 'bookings.detail.could_not_load'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _cancelBooking() async {
    if (_details == null) return;
    final isLender = _isLender();
    final counterparty = _details!.counterpartyNameFor(
          _currentApartmentId ?? '',
        ) ??
        (isLender
            ? 'bookings.detail.the_borrower'.tr()
            : 'bookings.detail.the_lender'.tr());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('bookings.cancel_dialog_title'.tr()),
        content: Text('bookings.cancel_dialog_message'.tr(namedArgs: {'counterparty': counterparty})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('bookings.keep_it'.tr()),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('bookings.cancel_booking'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _bookingService.cancelBooking(_details!.booking.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppSnack.error(context, 'bookings.detail.could_not_load'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  bool _isLender() {
    final d = _details;
    if (d == null || _currentApartmentId == null) return false;
    return _currentApartmentId == d.booking.lenderApartmentId;
  }

  ({String label, StatusTone tone, IconData icon}) _statusVisual(
      BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:
        return (
          label: 'bookings.detail.status_pending'.tr(),
          tone: StatusTone.warning,
          icon: Icons.hourglass_top_rounded,
        );
      case BookingStatus.approved:
        return (
          label: 'bookings.detail.status_approved'.tr(),
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case BookingStatus.rejected:
        return (
          label: 'bookings.detail.status_declined'.tr(),
          tone: StatusTone.danger,
          icon: Icons.cancel_outlined,
        );
      case BookingStatus.cancelled:
        return (
          label: 'bookings.detail.status_cancelled'.tr(),
          tone: StatusTone.neutral,
          icon: Icons.block_rounded,
        );
      case BookingStatus.completed:
        return (
          label: 'bookings.detail.status_completed'.tr(),
          tone: StatusTone.info,
          icon: Icons.done_all_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('bookings.detail.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_details == null) {
      return Scaffold(
        appBar: AppBar(title: Text('bookings.detail.title'.tr())),
        body: Center(child: Text('bookings.detail.not_found'.tr())),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = _details!;
    final b = d.booking;
    final isLender = _isLender();
    final vis = _statusVisual(b.status);
    final dateFmt = DateFormat('EEE MMM d, y');
    final timeFmt = DateFormat('h:mm a');

    final spotLabel = d.spotIdentifier != null
        ? 'bookings.detail.spot_label'.tr(namedArgs: {'id': d.spotIdentifier!})
        : 'bookings.detail.parking_booking'.tr();
    final counterpartyLabel = isLender
        ? (d.borrowerDisplayName ?? 'bookings.detail.borrower_label'.tr())
        : (d.lenderDisplayName ?? 'bookings.detail.lender_label'.tr());
    final counterpartyRole = isLender
        ? 'bookings.detail.borrower_label'.tr()
        : 'bookings.detail.lender_label'.tr();

    return Scaffold(
      appBar: AppBar(title: Text('bookings.detail.title'.tr())),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(
                  spotLabel: spotLabel,
                  counterpartyLabel: counterpartyLabel,
                  counterpartyRole: counterpartyRole,
                  status: vis,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'bookings.detail.when_label'.tr(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _TimeRow(
                          label: 'bookings.detail.starts'.tr(),
                          date: dateFmt.format(b.startTime.toLocal()),
                          time: timeFmt.format(b.startTime.toLocal()),
                        ),
                        const SizedBox(height: 12),
                        Divider(color: scheme.outlineVariant),
                        const SizedBox(height: 12),
                        _TimeRow(
                          label: 'bookings.detail.ends'.tr(),
                          date: dateFmt.format(b.endTime.toLocal()),
                          time: timeFmt.format(b.endTime.toLocal()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (b.status == BookingStatus.pending && isLender)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _approveBooking(false),
                          icon: Icon(Icons.close_rounded, color: scheme.error),
                          label: Text('bookings.detail.decline'.tr(),
                              style: TextStyle(color: scheme.error)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: scheme.error),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _approveBooking(true),
                          icon: const Icon(Icons.check_rounded),
                          label: Text('bookings.detail.approve'.tr()),
                        ),
                      ),
                    ],
                  )
                else if (b.status == BookingStatus.pending ||
                    b.status == BookingStatus.approved)
                  OutlinedButton.icon(
                    onPressed: _cancelBooking,
                    icon: Icon(Icons.close_rounded, color: scheme.error),
                    label: Text('bookings.cancel_booking'.tr(),
                        style: TextStyle(color: scheme.error)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: scheme.error),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(bookingId: b.id),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text('bookings.detail.open_chat'.tr()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String spotLabel;
  final String counterpartyLabel;
  final String counterpartyRole;
  final ({String label, StatusTone tone, IconData icon}) status;

  const _HeaderCard({
    required this.spotLabel,
    required this.counterpartyLabel,
    required this.counterpartyRole,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
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
                      Text(spotLabel, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        '$counterpartyRole · $counterpartyLabel',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                label: status.label,
                tone: status.tone,
                icon: status.icon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String date;
  final String time;
  const _TimeRow({
    required this.label,
    required this.date,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                time,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
