import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/building.dart';

class BuildingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Join building (direct database access - no edge function required)
  Future<Map<String, dynamic>> joinBuilding({
    required String inviteCode,
    String? displayName,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Find building by invite code
    final buildingResponse = await _supabase
        .from('buildings')
        .select('id, name, approval_required')
        .eq('invite_code', inviteCode.toUpperCase())
        .maybeSingle();

    if (buildingResponse == null) {
      throw Exception('Invalid invite code');
    }

    final building = buildingResponse;
    final buildingId = building['id'] as String;
    final approvalRequired = building['approval_required'] as bool;

    // Determine status based on approval_required
    final status = approvalRequired ? 'pending' : 'approved';

    // Check if profile exists
    final existingProfileResponse = await _supabase
        .from('profiles')
        .select('id, building_id, status')
        .eq('id', user.id)
        .maybeSingle();

    // Prepare profile data
    final profileData = <String, dynamic>{
      'id': user.id,
      'building_id': buildingId,
      'status': status,
    };

    if (displayName != null && displayName.isNotEmpty) {
      profileData['display_name'] = displayName;
    }

    // Update or insert profile
    if (existingProfileResponse != null) {
      final existingProfile = existingProfileResponse;
      // Check if user already belongs to a different building
      if (existingProfile['building_id'] != null &&
          existingProfile['building_id'] != buildingId) {
        throw Exception('User already belongs to a different building');
      }

      // Update existing profile
      await _supabase
          .from('profiles')
          .update(profileData)
          .eq('id', user.id);
    } else {
      // Insert new profile
      await _supabase.from('profiles').insert(profileData);
    }

    return {
      'success': true,
      'building': {'id': buildingId, 'name': building['name']},
      'status': status,
      'requires_approval': approvalRequired,
    };
  }

  // Get all buildings (for browsing/joining)
  Future<List<Building>> getAllBuildings() async {
    final response = await _supabase
        .from('buildings')
        .select()
        .order('name', ascending: true);

    return (response as List).map((json) => Building.fromJson(json)).toList();
  }

  // Get building by ID
  Future<Building?> getBuildingById(String buildingId) async {
    final response = await _supabase
        .from('buildings')
        .select()
        .eq('id', buildingId)
        .maybeSingle();

    if (response == null) return null;
    return Building.fromJson(response);
  }
}
