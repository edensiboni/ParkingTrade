import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/spot_waitlist_entry.dart';

/// Waitlist for parking spots (Roadmap 1.1).
///
/// Residents join a waitlist for a spot + desired time range when no
/// availability covers it. DB triggers (migration 032) flip entries to
/// `matched` when an overlapping availability window opens or an approved
/// booking is cancelled. Matching is informational — booking still goes
/// through the normal create-booking-request flow.
class WaitlistService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Resolve the current user's apartment_id (null if not yet assigned).
  Future<String?> _currentApartmentId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    final row = await _supabase
        .from('profiles')
        .select('apartment_id')
        .eq('id', user.id)
        .maybeSingle();
    return row?['apartment_id'] as String?;
  }

  /// Join the waitlist for [spotId] over the desired window.
  ///
  /// Times are normalized the same way as BookingService.createBookingRequest:
  /// the local wall-clock values are recorded as UTC, matching how
  /// availability periods are stored.
  Future<SpotWaitlistEntry> joinWaitlist({
    required String spotId,
    required DateTime desiredStart,
    required DateTime desiredEnd,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final apartmentId = await _currentApartmentId();
    if (apartmentId == null) {
      throw Exception('Your profile is not linked to an apartment yet');
    }

    final localStart = desiredStart.toLocal();
    final localEnd = desiredEnd.toLocal();
    final utcStart = DateTime.utc(localStart.year, localStart.month,
        localStart.day, localStart.hour, localStart.minute);
    final utcEnd = DateTime.utc(localEnd.year, localEnd.month, localEnd.day,
        localEnd.hour, localEnd.minute);

    try {
      final row = await _supabase
          .from('spot_waitlist')
          .insert({
            'spot_id': spotId,
            'requester_apartment_id': apartmentId,
            'created_by_profile_id': user.id,
            'desired_start': utcStart.toIso8601String(),
            'desired_end': utcEnd.toIso8601String(),
          })
          .select('*, parking_spots(spot_identifier)')
          .single();
      return SpotWaitlistEntry.fromJson(row);
    } on PostgrestException catch (e) {
      // Partial unique index: one active entry per apartment per spot.
      if (e.code == '23505') {
        throw Exception('You are already on the waitlist for this spot');
      }
      rethrow;
    }
  }

  /// Waitlist entries for the current user's apartment (waiting + matched),
  /// newest first, with the spot identifier joined in.
  Future<List<SpotWaitlistEntry>> getMyWaitlist() async {
    final apartmentId = await _currentApartmentId();
    if (apartmentId == null) return [];

    final rows = await _supabase
        .from('spot_waitlist')
        .select('*, parking_spots(spot_identifier)')
        .eq('requester_apartment_id', apartmentId)
        .inFilter('status', ['waiting', 'matched'])
        .order('created_at', ascending: false);

    return (rows as List)
        .map((json) => SpotWaitlistEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Cancel a waitlist entry (the only transition RLS allows clients).
  Future<void> cancelEntry(String entryId) async {
    await _supabase
        .from('spot_waitlist')
        .update({'status': 'cancelled', 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', entryId);
  }
}
