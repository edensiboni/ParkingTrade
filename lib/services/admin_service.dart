import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class AdminService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Profile>> getPendingMembers() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final adminProfile = await _supabase
        .from('profiles')
        .select('building_id, role')
        .eq('id', user.id)
        .single();

    if (adminProfile['role'] != 'admin') {
      throw Exception('Only admins can view pending members');
    }

    final buildingId = adminProfile['building_id'] as String?;
    if (buildingId == null) throw Exception('No building assigned');

    final response = await _supabase
        .from('profiles')
        .select()
        .eq('building_id', buildingId)
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return (response as List).map((json) => Profile.fromJson(json)).toList();
  }

  Future<List<Profile>> getBuildingMembers() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final adminProfile = await _supabase
        .from('profiles')
        .select('building_id, role')
        .eq('id', user.id)
        .single();

    if (adminProfile['role'] != 'admin') {
      throw Exception('Only admins can view building members');
    }

    final buildingId = adminProfile['building_id'] as String?;
    if (buildingId == null) throw Exception('No building assigned');

    final response = await _supabase
        .from('profiles')
        .select()
        .eq('building_id', buildingId)
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
}
