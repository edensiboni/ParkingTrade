import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_request.dart';
import '../models/parking_spot.dart';
import '../services/parking_spot_service.dart';

class BookingService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _spotService = ParkingSpotService();

  // Create booking request (direct database access - no edge function required)
  Future<BookingRequest> createBookingRequest({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Get borrower profile
    final borrowerProfileResponse = await _supabase
        .from('profiles')
        .select('id, building_id, status')
        .eq('id', user.id)
        .maybeSingle();

    if (borrowerProfileResponse == null) {
      throw Exception('Borrower profile not found');
    }

    final borrowerProfile = borrowerProfileResponse;
    final buildingId = borrowerProfile['building_id'] as String?;
    
    if (buildingId == null || borrowerProfile['status'] != 'approved') {
      throw Exception('Borrower must be an approved member of a building');
    }

    // Get parking spot
    final spotResponse = await _supabase
        .from('parking_spots')
        .select('id, resident_id, building_id, is_active')
        .eq('id', spotId)
        .maybeSingle();

    if (spotResponse == null) {
      throw Exception('Parking spot not found');
    }

    final spot = spotResponse;
    if (!spot['is_active']) {
      throw Exception('Parking spot is not active');
    }

    // Verify same building
    if (spot['building_id'] != buildingId) {
      throw Exception('Borrower and spot must be in the same building');
    }

    // Prevent self-booking
    if (spot['resident_id'] == user.id) {
      throw Exception('Cannot request your own parking spot');
    }

    // Check for overlapping APPROVED bookings (partial bookings allowed - only approved bookings block)
    // This allows multiple pending bookings and partial bookings of the same availability period
    // Two bookings overlap if: start1 < end2 AND end1 > start2
    // We need to check: startTime < existing.end AND endTime > existing.start
    try {
      final allApprovedBookings = await _supabase
          .from('booking_requests')
          .select('start_time, end_time')
          .eq('spot_id', spotId)
          .eq('status', 'approved');

      // Check for overlaps manually
      if (allApprovedBookings.isNotEmpty) {
        for (final booking in allApprovedBookings) {
          final existingStart = DateTime.parse(booking['start_time'] as String);
          final existingEnd = DateTime.parse(booking['end_time'] as String);
          
          // Check if time ranges overlap
          if (startTime.isBefore(existingEnd) && endTime.isAfter(existingStart)) {
            throw Exception('This time slot overlaps with an existing approved booking');
          }
        }
      }
    } catch (e) {
      // If overlap check fails, rethrow
      if (e.toString().contains('overlaps')) {
        rethrow;
      }
      // Otherwise, log but continue (might be RLS issue, but we'll try insert anyway)
      print('Warning: Could not check for overlapping bookings: $e');
    }

    // Create booking request
    // CRITICAL FIX: Treat the input DateTime as "naive" local time
    // and convert it to UTC explicitly, same as availability periods
    final localStart = startTime.toLocal();
    final localEnd = endTime.toLocal();
    
    // Create UTC DateTime with the same date/time components
    // This ensures the date doesn't shift when stored
    final utcStart = DateTime.utc(
      localStart.year,
      localStart.month,
      localStart.day,
      localStart.hour,
      localStart.minute,
    );
    final utcEnd = DateTime.utc(
      localEnd.year,
      localEnd.month,
      localEnd.day,
      localEnd.hour,
      localEnd.minute,
    );
    
    try {
      final response = await _supabase
        .from('booking_requests')
        .insert({
          'spot_id': spotId,
          'borrower_id': user.id,
          'lender_id': spot['resident_id'],
          'start_time': utcStart.toIso8601String(),
          'end_time': utcEnd.toIso8601String(),
          'status': 'pending',
        })
        .select()
        .single();

      return BookingRequest.fromJson(response);
    } catch (e) {
      // Provide more detailed error message
      final errorMessage = e.toString();
      if (errorMessage.contains('permission') || errorMessage.contains('policy')) {
        throw Exception('Permission denied. Please check your account status.');
      } else if (errorMessage.contains('overlap') || errorMessage.contains('constraint')) {
        throw Exception('This time slot overlaps with an existing approved booking');
      } else {
        throw Exception('Failed to create booking: ${errorMessage.replaceAll('Exception: ', '')}');
      }
    }
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
  // Optionally filter by time period to show only spots available during that time
  Future<List<ParkingSpot>> getAvailableSpots({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
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

    final allSpots = (response as List).map((json) => ParkingSpot.fromJson(json)).toList();

    // If time period is specified, filter by availability
    if (startTime != null && endTime != null) {
      final availableSpots = <ParkingSpot>[];
      for (final spot in allSpots) {
        final isAvailable = await _spotService.isSpotAvailable(
          spotId: spot.id,
          startTime: startTime,
          endTime: endTime,
        );
        if (isAvailable) {
          availableSpots.add(spot);
        }
      }
      return availableSpots;
    }

    return allSpots;
  }
}
