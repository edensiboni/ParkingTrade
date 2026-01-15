import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import '../../models/booking_request.dart';
import '../../models/profile.dart';
import 'booking_detail_screen.dart';
import 'request_spot_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> with SingleTickerProviderStateMixin {
  final _bookingService = BookingService();
  late TabController _tabController;
  List<BookingRequest> _activeBookings = [];
  List<BookingRequest> _pendingRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final [activeBookings, pendingRequests] = await Future.wait([
        _bookingService.getActiveBookings(),
        _bookingService.getPendingBookingsForLender(),
      ]);

      setState(() {
        _activeBookings = activeBookings;
        _pendingRequests = pendingRequests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bookings: $e')),
        );
      }
    }
  }

  String _getBookingStatusText(BookingRequest booking, Profile? currentProfile) {
    if (booking.borrowerId == currentProfile?.id) {
      switch (booking.status) {
        case BookingStatus.pending:
          return 'Waiting for approval';
        case BookingStatus.approved:
          return 'Approved';
        case BookingStatus.rejected:
          return 'Rejected';
        case BookingStatus.cancelled:
          return 'Cancelled';
        case BookingStatus.completed:
          return 'Completed';
      }
    } else {
      switch (booking.status) {
        case BookingStatus.pending:
          return 'Pending your approval';
        case BookingStatus.approved:
          return 'Approved by you';
        case BookingStatus.rejected:
          return 'Rejected by you';
        case BookingStatus.cancelled:
          return 'Cancelled';
        case BookingStatus.completed:
          return 'Completed';
      }
    }
  }

  Widget _buildBookingItem(BookingRequest booking) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: const Text('Spot Booking'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${booking.startTime.toString().substring(0, 16)} - ${booking.endTime.toString().substring(0, 16)}',
            ),
            Text(_getBookingStatusText(booking, null)),
          ],
        ),
        trailing: Icon(
          _getStatusIcon(booking.status),
          color: _getStatusColor(booking.status),
        ),
        onTap: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => BookingDetailScreen(bookingId: booking.id),
            ),
          );
          if (result == true) {
            _loadBookings();
          }
        },
      ),
    );
  }

  IconData _getStatusIcon(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return Icons.pending;
      case BookingStatus.approved:
        return Icons.check_circle;
      case BookingStatus.rejected:
        return Icons.cancel;
      case BookingStatus.cancelled:
        return Icons.cancel_outlined;
      case BookingStatus.completed:
        return Icons.done_all;
    }
  }

  Color _getStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.approved:
        return Colors.green;
      case BookingStatus.rejected:
        return Colors.red;
      case BookingStatus.cancelled:
        return Colors.grey;
      case BookingStatus.completed:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Pending'),
            Tab(text: 'Request Spot'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Active Bookings Tab
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _activeBookings.isEmpty
                  ? const Center(child: Text('No active bookings'))
                  : RefreshIndicator(
                      onRefresh: _loadBookings,
                      child: ListView.builder(
                        itemCount: _activeBookings.length,
                        itemBuilder: (context, index) {
                          return _buildBookingItem(_activeBookings[index]);
                        },
                      ),
                    ),

          // Pending Requests Tab (for lenders)
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _pendingRequests.isEmpty
                  ? const Center(child: Text('No pending requests'))
                  : RefreshIndicator(
                      onRefresh: _loadBookings,
                      child: ListView.builder(
                        itemCount: _pendingRequests.length,
                        itemBuilder: (context, index) {
                          return _buildBookingItem(_pendingRequests[index]);
                        },
                      ),
                    ),

          // Request Spot Tab
          RequestSpotScreen(onBookingCreated: _loadBookings),
        ],
      ),
    );
  }
}

