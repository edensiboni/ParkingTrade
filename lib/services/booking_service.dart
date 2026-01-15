import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_request.dart';
import '../models/parking_spot.dart';

class BookingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Create booking request via Edge Function
  Future<BookingRequest> createBookingRequest({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final response = await _supabase.functions.invoke(
      'create-booking-request',
      body: {
        'spot_id': spotId,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Failed to create booking request');
    }

    return BookingRequest.fromJson(response.data['booking']);
  }

  // Approve or reject booking via Edge Function
  Future<BookingRequest> approveBooking({
    required String bookingId,
    required bool approve,
  }) async {
    final response = await _supabase.functions.invoke(
      'approve-booking',
      body: {
        'booking_id': bookingId,
        'action': approve ? 'approve' : 'reject',
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Failed to update booking');
    }

    return BookingRequest.fromJson(response.data['booking']);
  }

  // Get user's bookings (as borrower or lender)
  Future<List<BookingRequest>> getUserBookings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('booking_requests')
        .select()
        .or('borrower_id.eq.${user.id},lender_id.eq.${user.id}')
        .order('created_at', ascending: false);

    return (response as List).map((json) => BookingRequest.fromJson(json)).toList();
  }

  // Get pending bookings for lender
  Future<List<BookingRequest>> getPendingBookingsForLender() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('booking_requests')
        .select()
        .eq('lender_id', user.id)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return (response as List).map((json) => BookingRequest.fromJson(json)).toList();
  }

  // Get active bookings
  Future<List<BookingRequest>> getActiveBookings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('booking_requests')
        .select()
        .or('borrower_id.eq.${user.id},lender_id.eq.${user.id}')
        .inFilter('status', ['pending', 'approved'])
        .order('start_time', ascending: true);

    return (response as List).map((json) => BookingRequest.fromJson(json)).toList();
  }

  // Get booking by ID
  Future<BookingRequest?> getBookingById(String bookingId) async {
    final response = await _supabase
        .from('booking_requests')
        .select()
        .eq('id', bookingId)
        .maybeSingle();

    if (response == null) return null;
    return BookingRequest.fromJson(response);
  }

  // Cancel booking
  Future<void> cancelBooking(String bookingId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Get booking to verify ownership
    final booking = await getBookingById(bookingId);
    if (booking == null) throw Exception('Booking not found');

    if (booking.borrowerId != user.id && booking.lenderId != user.id) {
      throw Exception('Not authorized to cancel this booking');
    }

    await _supabase
        .from('booking_requests')
        .update({'status': 'cancelled'})
        .eq('id', bookingId);
  }

  // Get available parking spots in building
  Future<List<ParkingSpot>> getAvailableSpots() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final profileResponse = await _supabase
        .from('profiles')
        .select('building_id')
        .eq('id', user.id)
        .single();

    final buildingId = profileResponse['building_id'] as String?;
    if (buildingId == null) throw Exception('User not in a building');

    final response = await _supabase
        .from('parking_spots')
        .select()
        .eq('building_id', buildingId)
        .eq('is_active', true)
        .neq('resident_id', user.id); // Exclude user's own spots

    return (response as List).map((json) => ParkingSpot.fromJson(json)).toList();
  }
}
