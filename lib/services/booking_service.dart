import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_request.dart';
import '../models/parking_spot.dart';
import '../services/parking_spot_service.dart';

/// Enriched view of a booking with the joined context a human actually
/// wants to see: the physical spot identifier and the counterparty's
/// display name. Two light extra reads on top of `getBookingById`, but
/// worth it — SPEC §8.4 says users interact by display name, not UUID.
class BookingDetails {
  final BookingRequest booking;
  final String? spotIdentifier;
  final String? borrowerDisplayName;
  final String? lenderDisplayName;

  const BookingDetails({
    required this.booking,
    this.spotIdentifier,
    this.borrowerDisplayName,
    this.lenderDisplayName,
  });

  /// The other party's display name from the current user's perspective.
  String? counterpartyNameFor(String currentUserId) {
    if (currentUserId == booking.borrowerId) return lenderDisplayName;
    if (currentUserId == booking.lenderId) return borrowerDisplayName;
    return null;
  }
}

class BookingService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _spotService = ParkingSpotService();

  // Create booking request via Edge Function.
  //
  // The edge function is the canonical path: it enforces building membership,
  // approval status, same-building check, self-booking prevention, and triggers
  // a push notification to the lender. The DB-level exclusion constraint
  // guarantees no two approved bookings can overlap, even without a
  // client-side check.
  Future<BookingRequest> createBookingRequest({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Preserve local wall-clock meaning: treat the input as local time and
    // record the same Y/M/D/H/M in UTC, matching availability-period storage.
    final localStart = startTime.toLocal();
    final localEnd = endTime.toLocal();
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

    final response = await _supabase.functions.invoke(
      'create-booking-request',
      body: {
        'spot_id': spotId,
        'start_time': utcStart.toIso8601String(),
        'end_time': utcEnd.toIso8601String(),
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final message = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Failed to create booking';
      throw Exception(message);
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

  /// Fetch a booking alongside the joined human context (spot identifier,
  /// borrower + lender display names). Returns null if the booking itself
  /// is missing; missing joined rows (e.g. a deleted profile) just come
  /// back as null fields inside [BookingDetails].
  Future<BookingDetails?> getBookingDetails(String bookingId) async {
    final booking = await getBookingById(bookingId);
    if (booking == null) return null;

    // Fire the side reads in parallel; each is best-effort.
    final results = await Future.wait([
      _fetchSpotIdentifier(booking.spotId),
      _fetchDisplayName(booking.borrowerId),
      _fetchDisplayName(booking.lenderId),
    ]);

    return BookingDetails(
      booking: booking,
      spotIdentifier: results[0],
      borrowerDisplayName: results[1],
      lenderDisplayName: results[2],
    );
  }

  Future<String?> _fetchSpotIdentifier(String spotId) async {
    try {
      final row = await _supabase
          .from('parking_spots')
          .select('spot_identifier')
          .eq('id', spotId)
          .maybeSingle();
      return row?['spot_identifier'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchDisplayName(String profileId) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', profileId)
          .maybeSingle();
      return row?['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Batch the joined reads for a list of bookings — one query per table
  /// instead of N per row. Returns a map keyed by [BookingRequest.id].
  Future<Map<String, BookingDetails>> getDetailsForBookings(
      List<BookingRequest> bookings) async {
    if (bookings.isEmpty) return const {};

    final spotIds = bookings.map((b) => b.spotId).toSet().toList();
    final profileIds = <String>{
      for (final b in bookings) ...[b.borrowerId, b.lenderId],
    }.toList();

    final spotMap = <String, String>{};
    final nameMap = <String, String>{};

    try {
      final spotRows = await _supabase
          .from('parking_spots')
          .select('id, spot_identifier')
          .inFilter('id', spotIds);
      for (final row in (spotRows as List)) {
        final id = row['id'] as String?;
        final ident = row['spot_identifier'] as String?;
        if (id != null && ident != null) spotMap[id] = ident;
      }
    } catch (_) {
      // Leave spotMap empty — the UI falls back to "Parking booking".
    }

    try {
      final nameRows = await _supabase
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', profileIds);
      for (final row in (nameRows as List)) {
        final id = row['id'] as String?;
        final name = row['display_name'] as String?;
        if (id != null && name != null && name.isNotEmpty) {
          nameMap[id] = name;
        }
      }
    } catch (_) {
      // Leave nameMap empty — the UI falls back gracefully.
    }

    return {
      for (final b in bookings)
        b.id: BookingDetails(
          booking: b,
          spotIdentifier: spotMap[b.spotId],
          borrowerDisplayName: nameMap[b.borrowerId],
          lenderDisplayName: nameMap[b.lenderId],
        ),
    };
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
