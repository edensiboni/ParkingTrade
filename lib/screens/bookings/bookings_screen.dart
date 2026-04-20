import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/booking_service.dart';
import '../../models/booking_request.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';
import 'booking_detail_screen.dart';
import 'available_spots_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  final _bookingService = BookingService();
  late TabController _tabController;
  List<BookingRequest> _myBookings = [];
  List<BookingRequest> _pendingRequests = [];
  Map<String, BookingDetails> _detailsById = const {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBookings();
  }

  void switchToMyBookings() {
    if (mounted) {
      _tabController.animateTo(1);
      _loadBookings();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);

    try {
      final [myBookings, pendingRequests] = await Future.wait([
        _bookingService.getUserBookings(),
        _bookingService.getPendingBookingsForLender(),
      ]);
      // Merge both lists (unique by id) so we fetch joined data in one batch.
      final merged = <String, BookingRequest>{};
      for (final b in [...myBookings, ...pendingRequests]) {
        merged[b.id] = b;
      }
      final details = await _bookingService
          .getDetailsForBookings(merged.values.toList());
      if (!mounted) return;
      setState(() {
        _myBookings = myBookings;
        _pendingRequests = pendingRequests;
        _detailsById = details;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'Could not load bookings: $e');
    }
  }

  Future<void> _cancelBooking(BookingRequest booking) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final isBorrower = booking.borrowerId == userId;
    final details = _detailsById[booking.id];
    final counterparty = details?.counterpartyNameFor(userId ?? '') ??
        (isBorrower ? 'The lender' : 'The borrower');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Text('$counterparty will be notified.'),
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

    if (confirmed != true || !mounted) return;

    try {
      await _bookingService.cancelBooking(booking.id);
      if (mounted) {
        AppSnack.success(context, 'Booking cancelled');
        _loadBookings();
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(
            context,
            'Could not cancel: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  _StatusDescriptor _describeStatus(BookingRequest booking) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final isBorrower = booking.borrowerId == userId;
    switch (booking.status) {
      case BookingStatus.pending:
        return _StatusDescriptor(
          label: isBorrower ? 'Waiting for approval' : 'Needs your review',
          tone: StatusTone.warning,
          icon: Icons.hourglass_top_rounded,
        );
      case BookingStatus.approved:
        return _StatusDescriptor(
          label: isBorrower ? 'Approved' : 'You approved',
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case BookingStatus.rejected:
        return _StatusDescriptor(
          label: isBorrower ? 'Declined' : 'You declined',
          tone: StatusTone.danger,
          icon: Icons.cancel_outlined,
        );
      case BookingStatus.cancelled:
        return _StatusDescriptor(
          label: 'Cancelled',
          tone: StatusTone.neutral,
          icon: Icons.block_rounded,
        );
      case BookingStatus.completed:
        return _StatusDescriptor(
          label: 'Completed',
          tone: StatusTone.info,
          icon: Icons.done_all_rounded,
        );
    }
  }

  Widget _buildBookingCard(BookingRequest booking, {bool showCancel = false}) {
    final user = Supabase.instance.client.auth.currentUser;
    final canCancel = showCancel &&
        booking.borrowerId == user?.id &&
        (booking.status == BookingStatus.pending ||
            booking.status == BookingStatus.approved);

    final status = _describeStatus(booking);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFmt = DateFormat('EEE MMM d • h:mm a');

    final details = _detailsById[booking.id];
    final isBorrower = booking.borrowerId == user?.id;
    final title = details?.spotIdentifier != null
        ? 'Spot ${details!.spotIdentifier}'
        : 'Parking booking';
    final counterpartyName = details?.counterpartyNameFor(user?.id ?? '');
    final counterpartyRole = isBorrower ? 'Lender' : 'Borrower';
    final subtitle = counterpartyName != null
        ? '$counterpartyRole · $counterpartyName'
        : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => BookingDetailScreen(bookingId: booking.id),
            ),
          );
          if (result == true) _loadBookings();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.local_parking_rounded,
                        size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          subtitle ?? dateFmt.format(booking.startTime.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    label: status.label,
                    tone: status.tone,
                    icon: status.icon,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${dateFmt.format(booking.startTime.toLocal())}  →  ${dateFmt.format(booking.endTime.toLocal())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (canCancel) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _cancelBooking(booking),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: scheme.error),
                    label: Text(
                      'Cancel',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingLabel = _pendingRequests.isEmpty
        ? 'Pending'
        : 'Pending (${_pendingRequests.length})';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Available'),
            const Tab(text: 'My bookings'),
            Tab(text: pendingLabel),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          AvailableSpotsScreen(
            onBookingCreated: () {
              _loadBookings();
              switchToMyBookings();
            },
          ),
          _buildMyBookingsList(),
          _buildPendingList(),
        ],
      ),
    );
  }

  Widget _buildMyBookingsList() {
    if (_isLoading) return const SkeletonList(count: 3);
    if (_myBookings.isEmpty) {
      return const EmptyState(
        icon: Icons.event_note_rounded,
        title: 'No bookings yet',
        message: 'Book a spot from the Available tab to see it here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _myBookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) =>
            _buildBookingCard(_myBookings[i], showCancel: true),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_isLoading) return const SkeletonList(count: 3);
    if (_pendingRequests.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Inbox zero',
        message: 'No requests waiting on your approval.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingRequests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _buildBookingCard(_pendingRequests[i]),
      ),
    );
  }
}

class _StatusDescriptor {
  final String label;
  final StatusTone tone;
  final IconData icon;
  _StatusDescriptor({
    required this.label,
    required this.tone,
    required this.icon,
  });
}
