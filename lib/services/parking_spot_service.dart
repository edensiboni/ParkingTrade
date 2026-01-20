import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/parking_spot.dart';
import '../models/spot_availability_period.dart';

class ParkingSpotService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get user's parking spots
  Future<List<ParkingSpot>> getUserSpots() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('parking_spots')
        .select()
        .eq('resident_id', user.id)
        .order('created_at', ascending: false);

    return (response as List).map((json) => ParkingSpot.fromJson(json)).toList();
  }

  // Add a new parking spot
  Future<ParkingSpot> addSpot({
    required String buildingId,
    required String spotIdentifier,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('parking_spots')
        .insert({
          'resident_id': user.id,
          'building_id': buildingId,
          'spot_identifier': spotIdentifier,
          'is_active': true,
        })
        .select()
        .single();

    return ParkingSpot.fromJson(response);
  }

  // Update spot (toggle active/inactive or update identifier)
  Future<ParkingSpot> updateSpot({
    required String spotId,
    bool? isActive,
    String? spotIdentifier,
  }) async {
    final updates = <String, dynamic>{};
    if (isActive != null) {
      updates['is_active'] = isActive;
    }
    if (spotIdentifier != null) {
      updates['spot_identifier'] = spotIdentifier;
    }

    if (updates.isEmpty) {
      throw Exception('No updates provided');
    }

    final response = await _supabase
        .from('parking_spots')
        .update(updates)
        .eq('id', spotId)
        .select()
        .single();

    return ParkingSpot.fromJson(response);
  }

  // Delete parking spot
  Future<void> deleteSpot(String spotId) async {
    await _supabase
        .from('parking_spots')
        .delete()
        .eq('id', spotId);
  }

  // Get availability periods for a spot
  Future<List<SpotAvailabilityPeriod>> getAvailabilityPeriods(String spotId) async {
    final response = await _supabase
        .from('spot_availability_periods')
        .select()
        .eq('spot_id', spotId)
        .order('start_time', ascending: true);

    return (response as List)
        .map((json) => SpotAvailabilityPeriod.fromJson(json))
        .toList();
  }

  // Add availability period for a spot
  Future<SpotAvailabilityPeriod> addAvailabilityPeriod({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
    bool isRecurring = false,
    String? recurringPattern,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Verify user owns the spot
    final spot = await _supabase
        .from('parking_spots')
        .select('resident_id')
        .eq('id', spotId)
        .single();

    if (spot['resident_id'] != user.id) {
      throw Exception('You can only set availability for your own spots');
    }

    final response = await _supabase
        .from('spot_availability_periods')
        .insert({
          'spot_id': spotId,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'is_recurring': isRecurring,
          if (recurringPattern != null) 'recurring_pattern': recurringPattern,
        })
        .select()
        .single();

    return SpotAvailabilityPeriod.fromJson(response);
  }

  // Delete availability period
  Future<void> deleteAvailabilityPeriod(String periodId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Note: RLS policy ensures only spot owners can delete their availability periods
    await _supabase
        .from('spot_availability_periods')
        .delete()
        .eq('id', periodId);
  }

  // Check if a spot is available during a time period
  Future<bool> isSpotAvailable({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    // Get all availability periods for this spot
    final periods = await getAvailabilityPeriods(spotId);

    if (periods.isEmpty) {
      // If no availability periods set, spot is always available (backward compatibility)
      return true;
    }

    // Check if requested time overlaps with any availability period
    for (final period in periods) {
      if (period.overlapsWith(startTime, endTime)) {
        return true;
      }
    }

    return false;
  }
}

