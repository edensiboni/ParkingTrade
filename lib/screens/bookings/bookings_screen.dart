import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/booking_service.dart';
import '../../models/booking_request.dart';
import '../../models/profile.dart';
import 'booking_detail_screen.dart';
import 'request_spot_screen.dart';
import 'available_spots_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> with SingleTickerProviderStateMixin {
  final _bookingService = BookingService();
  late TabController _tabController;
  List<BookingRequest> _myBookings = [];
  List<BookingRequest> _pendingRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadBookings();
  }

  // Method to switch to My Bookings tab (called after booking)
  void switchToMyBookings() {
    if (mounted) {
      _tabController.animateTo(1); // Switch to My Bookings tab (index 1)
      _loadBookings(); // Refresh bookings
    }
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
      final [myBookings, pendingRequests] = await Future.wait([
        _bookingService.getUserBookings(),
        _bookingService.getPendingBookingsForLender(),
      ]);

      setState(() {
        _myBookings = myBookings;
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

  Future<void> _cancelBooking(BookingRequest booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _bookingService.cancelBooking(booking.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadBookings(); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling booking: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
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

  Widget _buildBookingItem(BookingRequest booking, {bool showCancel = false}) {
    final user = Supabase.instance.client.auth.currentUser;
    final canCancel = showCancel && 
        booking.borrowerId == user?.id && 
        (booking.status == BookingStatus.pending || booking.status == BookingStatus.approved);

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCancel)
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red),
                onPressed: () => _cancelBooking(booking),
                tooltip: 'Cancel Booking',
              ),
            Icon(
              _getStatusIcon(booking.status),
              color: _getStatusColor(booking.status),
            ),
          ],
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
          isScrollable: true,
          tabs: const [
            Tab(text: 'Available Spots'),
            Tab(text: 'My Bookings'),
            Tab(text: 'Pending'),
            Tab(text: 'Request Spot'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Available Spots Tab (NEW - First tab)
          AvailableSpotsScreen(
            onBookingCreated: () {
              _loadBookings();
              switchToMyBookings();
            },
          ),

          // My Bookings Tab
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _myBookings.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.book_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No bookings yet'),
                          SizedBox(height: 8),
                          Text(
                            'Book a spot from Available Spots tab',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBookings,
                      child: ListView.builder(
                        itemCount: _myBookings.length,
                        itemBuilder: (context, index) {
                          return _buildBookingItem(_myBookings[index], showCancel: true);
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

