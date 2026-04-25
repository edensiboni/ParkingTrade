import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class AdminService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Resolve the building_id for the current admin by joining through their apartment.
  /// Throws if the caller is not an admin or has no apartment.
  Future<String> _resolveAdminBuildingId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final row = await _supabase
        .from('profiles')
        .select('role, apartments(building_id)')
        .eq('id', user.id)
        .single();

    if (row['role'] != 'admin') {
      throw Exception('Only admins can perform this action');
    }

    final buildingId =
        (row['apartments'] as Map<String, dynamic>?)?['building_id'] as String?;
    if (buildingId == null) throw Exception('Admin has no building assigned');

    return buildingId;
  }

  Future<List<Profile>> getPendingMembers() async {
    final buildingId = await _resolveAdminBuildingId();

    // Fetch profiles whose apartment belongs to this building with status='pending'.
    final response = await _supabase
        .from('profiles')
        .select('*, apartments!inner(building_id)')
        .eq('apartments.building_id', buildingId)
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return (response as List).map((json) => Profile.fromJson(json)).toList();
  }

  Future<List<Profile>> getBuildingMembers() async {
    final buildingId = await _resolveAdminBuildingId();

    final response = await _supabase
        .from('profiles')
        .select('*, apartments!inner(building_id)')
        .eq('apartments.building_id', buildingId)
        .order('created_at', ascending: true);

    return (response as List).map((json) => Profile.fromJson(json)).toList();
  }

  Future<Profile> manageMember({
    required String memberId,
    required String action,
  }) async {
    final response = await _supabase.functions.invoke(
      'manage-member',
      body: {
        'member_id': memberId,
        'action': action,
      },
    );

    if (response.status != 200) {
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      throw Exception(data['error'] ?? 'Failed to manage member');
    }

    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : response.data as Map<String, dynamic>;

    return Profile.fromJson(data['member']);
  }

  /// Sends a list of apartment/phone/spot objects to the admin-bulk-import
  /// edge function. Returns a summary map with 'imported' and optional 'errors'.
  Future<Map<String, dynamic>> bulkImport(
      List<Map<String, dynamic>> data) async {
    final response = await _supabase.functions.invoke(
      'admin-bulk-import',
      body: data,
    );

    // 207 means partial success — still return the body so the UI can report it.
    if (response.status != 200 &&
        response.status != 207 &&
        response.status != 201) {
      final body = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      throw Exception(
          (body as Map<String, dynamic>?)?['error'] ?? 'Bulk import failed');
    }

    final body = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : response.data as Map<String, dynamic>;

    return body;
  }
}
