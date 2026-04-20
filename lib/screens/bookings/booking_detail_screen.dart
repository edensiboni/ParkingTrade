import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  BookingRequest? _booking;
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
      final booking = await _bookingService.getBookingById(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'Could not load booking: $e');
    }
  }

  Future<void> _approveBooking(bool approve) async {
    if (_booking == null) return;
    setState(() => _isProcessing = true);
    try {
      await _bookingService.approveBooking(
        bookingId: _booking!.id,
        approve: approve,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) AppSnack.error(context, 'Error: $e');
    }
  }

  Future<void> _cancelBooking() async {
    if (_booking == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('The other party will be notified.'),
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
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _bookingService.cancelBooking(_booking!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppSnack.error(context, 'Error: $e');
    }
  }

  bool _isLender() {
    if (_booking == null) return false;
    return _authService.currentUser?.id == _booking!.lenderId;
  }

  ({String label, StatusTone tone, IconData icon}) _statusVisual(
      BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:
        return (
          label: 'Pending',
          tone: StatusTone.warning,
          icon: Icons.hourglass_top_rounded,
        );
      case BookingStatus.approved:
        return (
          label: 'Approved',
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case BookingStatus.rejected:
        return (
          label: 'Declined',
          tone: StatusTone.danger,
          icon: Icons.cancel_outlined,
        );
      case BookingStatus.cancelled:
        return (
          label: 'Cancelled',
          tone: StatusTone.neutral,
          icon: Icons.block_rounded,
        );
      case BookingStatus.completed:
        return (
          label: 'Completed',
          tone: StatusTone.info,
          icon: Icons.done_all_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = _booking!;
    final isLender = _isLender();
    final vis = _statusVisual(b.status);
    final dateFmt = DateFormat('EEE MMM d, y');
    final timeFmt = DateFormat('h:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Status',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            StatusChip(
                              label: vis.label,
                              tone: vis.tone,
                              icon: vis.icon,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _TimeRow(
                          label: 'Starts',
                          date: dateFmt.format(b.startTime.toLocal()),
                          time: timeFmt.format(b.startTime.toLocal()),
                        ),
                        const SizedBox(height: 12),
                        Divider(color: scheme.outlineVariant),
                        const SizedBox(height: 12),
                        _TimeRow(
                          label: 'Ends',
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
                          label: Text('Decline',
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
                          label: const Text('Approve'),
                        ),
                      ),
                    ],
                  )
                else if (b.status == BookingStatus.pending ||
                    b.status == BookingStatus.approved)
                  OutlinedButton.icon(
                    onPressed: _cancelBooking,
                    icon: Icon(Icons.close_rounded, color: scheme.error),
                    label: Text('Cancel booking',
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
                label: const Text('Open chat'),
              ),
            ),
          ),
        ],
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
