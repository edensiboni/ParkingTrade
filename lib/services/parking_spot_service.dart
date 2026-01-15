import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/parking_spot.dart';

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
}

