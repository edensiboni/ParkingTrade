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

  /// **Deprecated:** Do not use. The legacy `create-building` Edge Function
  /// targets the pre–apartment-centric schema (`profiles.building_id`) and
  /// does not set `apartment_id`, `role`, or `is_apartment_admin`.
  ///
  /// Building creation is done from the setup route (`/setup`,
  /// `CreateBuildingScreen`) by invoking the `create-building-admin` Edge Function.
  @Deprecated('Use setup flow / create-building-admin Edge Function')
  Future<Map<String, dynamic>> createBuilding({
    required String name,
    String? address,
    bool approvalRequired = false,
  }) async {
    throw UnimplementedError(
      'createBuilding is removed: use CreateBuildingScreen or invoke '
      'create-building-admin with building_name, optional address/lat/lng, '
      'and optional admin_display_name.',
    );
  }

  // Search buildings by name (client-side filter of getAllBuildings)
  Future<List<Building>> searchBuildings(String query) async {
    final all = await getAllBuildings();
    if (query.trim().isEmpty) return all;
    final lower = query.trim().toLowerCase();
    return all.where((b) => b.name.toLowerCase().contains(lower)).toList();
  }

  /// Update mutable fields on an existing building.
  ///
  /// Only the fields that are non-null are patched so callers can pass only
  /// the values they want to change.
  Future<Building> updateBuilding({
    required String buildingId,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    int? totalParkingSpots,
  }) async {
    final patch = <String, dynamic>{
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (totalParkingSpots != null)
        'total_parking_spots': totalParkingSpots,
    };

    if (patch.isEmpty) {
      // Nothing to update — fetch and return current state.
      final current = await getBuildingById(buildingId);
      if (current == null) throw Exception('Building not found');
      return current;
    }

    final response = await _supabase
        .from('buildings')
        .update(patch)
        .eq('id', buildingId)
        .select()
        .single();

    return Building.fromJson(response);
  }
}
