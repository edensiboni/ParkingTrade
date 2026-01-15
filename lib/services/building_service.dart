import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/building.dart';

class BuildingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Join building via Edge Function
  Future<Map<String, dynamic>> joinBuilding({
    required String inviteCode,
    String? displayName,
  }) async {
    final response = await _supabase.functions.invoke(
      'join-building',
      body: {
        'invite_code': inviteCode,
        if (displayName != null) 'display_name': displayName,
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Failed to join building');
    }

    return response.data;
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
