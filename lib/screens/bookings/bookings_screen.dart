import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  String? _currentApartmentId;
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
      final aptRow = await Supabase.instance.client
          .from('profiles')
          .select('apartment_id')
          .eq('id', Supabase.instance.client.auth.currentUser!.id)
          .maybeSingle();
      _currentApartmentId = aptRow?['apartment_id'] as String?;

      final [myBookings, pendingRequests] = await Future.wait([
        _bookingService.getUserBookings(),
        _bookingService.getPendingBookingsForLender(),
      ]);
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
      AppSnack.error(context, 'bookings.could_not_load'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _cancelBooking(BookingRequest booking) async {
    final aptId = _currentApartmentId ?? '';
    final isBorrower = booking.borrowerApartmentId == aptId;
    final details = _detailsById[booking.id];
    final counterparty = details?.counterpartyNameFor(aptId) ??
        (isBorrower ? 'bookings.lender'.tr() : 'bookings.borrower'.tr());
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

    if (confirmed != true || !mounted) return;

    try {
      await _bookingService.cancelBooking(booking.id);
      if (mounted) {
        AppSnack.success(context, 'bookings.booking_cancelled'.tr());
        _loadBookings();
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(
            context,
            'bookings.could_not_cancel'.tr(namedArgs: {'error': e.toString().replaceAll('Exception: ', '')}));
      }
    }
  }

  _StatusDescriptor _describeStatus(BookingRequest booking) {
    final isBorrower = booking.borrowerApartmentId == (_currentApartmentId ?? '');
    switch (booking.status) {
      case BookingStatus.pending:
        return _StatusDescriptor(
          label: isBorrower
              ? 'bookings.status_waiting_approval'.tr()
              : 'bookings.status_needs_review'.tr(),
          tone: StatusTone.warning,
          icon: Icons.hourglass_top_rounded,
        );
      case BookingStatus.approved:
        return _StatusDescriptor(
          label: isBorrower
              ? 'bookings.status_approved_borrower'.tr()
              : 'bookings.status_approved_lender'.tr(),
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case BookingStatus.rejected:
        return _StatusDescriptor(
          label: isBorrower
              ? 'bookings.status_declined_borrower'.tr()
              : 'bookings.status_declined_lender'.tr(),
          tone: StatusTone.danger,
          icon: Icons.cancel_outlined,
        );
      case BookingStatus.cancelled:
        return _StatusDescriptor(
          label: 'bookings.status_cancelled'.tr(),
          tone: StatusTone.neutral,
          icon: Icons.block_rounded,
        );
      case BookingStatus.completed:
        return _StatusDescriptor(
          label: 'bookings.status_completed'.tr(),
          tone: StatusTone.info,
          icon: Icons.done_all_rounded,
        );
    }
  }

  Widget _buildBookingCard(BookingRequest booking, {bool showCancel = false}) {
    final aptId = _currentApartmentId ?? '';
    final isBorrower = booking.borrowerApartmentId == aptId;
    final canCancel = showCancel &&
        isBorrower &&
        (booking.status == BookingStatus.pending ||
            booking.status == BookingStatus.approved);

    final status = _describeStatus(booking);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFmt = DateFormat('EEE MMM d • h:mm a');

    final details = _detailsById[booking.id];
    final title = details?.spotIdentifier != null
        ? 'bookings.spot_label'.tr(namedArgs: {'id': details!.spotIdentifier!})
        : 'bookings.parking_booking'.tr();
    final counterpartyName = details?.counterpartyNameFor(aptId);
    final counterpartyRole = isBorrower
        ? 'bookings.lender'.tr()
        : 'bookings.borrower'.tr();
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
                      'bookings.cancel'.tr(),
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
        ? 'bookings.tab_pending'.tr()
        : 'bookings.tab_pending_count'.tr(namedArgs: {'count': _pendingRequests.length.toString()});

    return Scaffold(
      appBar: AppBar(
        title: Text('bookings.title'.tr()),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'bookings.tab_available'.tr()),
            Tab(text: 'bookings.tab_my_bookings'.tr()),
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
      return EmptyState(
        icon: Icons.event_note_rounded,
        title: 'bookings.no_bookings_title'.tr(),
        message: 'bookings.no_bookings_message'.tr(),
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
      return EmptyState(
        icon: Icons.inbox_rounded,
        title: 'bookings.inbox_zero_title'.tr(),
        message: 'bookings.inbox_zero_message'.tr(),
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
