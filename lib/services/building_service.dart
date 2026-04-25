import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/building.dart';

class BuildingService {
  final SupabaseClient _supabase = Supabase.instance.client;

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

  // Create building via Edge Function (generates invite code, sets user as first member)
  Future<Map<String, dynamic>> createBuilding({
    required String name,
    String? address,
    bool approvalRequired = false,
  }) async {
    final response = await _supabase.functions.invoke(
      'create-building',
      body: {
        'name': name,
        if (address != null && address.isNotEmpty) 'address': address,
        'approval_required': approvalRequired,
      },
    );

    if (response.status != 200) {
      final msg = response.data is Map ? response.data['error'] : null;
      throw Exception(msg ?? 'Failed to create building');
    }

    final data = response.data as Map<String, dynamic>;
    return {
      'success': true,
      'building': {
        'id': data['building_id'],
        'name': data['name'],
      },
      'invite_code': data['invite_code'],
      'status': data['status'],
      'requires_approval': data['requires_approval'] as bool? ?? false,
    };
  }

  // Search buildings by name (client-side filter of getAllBuildings)
  Future<List<Building>> searchBuildings(String query) async {
    final all = await getAllBuildings();
    if (query.trim().isEmpty) return all;
    final lower = query.trim().toLowerCase();
    return all.where((b) => b.name.toLowerCase().contains(lower)).toList();
  }
}
