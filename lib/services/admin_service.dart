import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/authorized_apartment.dart';
import '../models/profile.dart';
import '../models/building.dart';
import 'building_service.dart';

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

  /// Returns the Building record for the current admin's building.
  Future<Building> getAdminBuilding() async {
    final buildingId = await _resolveAdminBuildingId();
    final building =
        await BuildingService().getBuildingById(buildingId);
    if (building == null) throw Exception('Building not found');
    return building;
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

  // ── Manage Apartments (authorized_apartments table) ────────────────────────

  /// Returns all authorized_apartments rows for the current admin's building.
  ///
  /// Each row carries a *list* of [Resident] objects (name + phone). See
  /// migration 019 for the schema move from `resident_phones TEXT[]` →
  /// `residents JSONB`.
  Future<List<AuthorizedApartment>> getAuthorizedApartments() async {
    final buildingId = await _resolveAdminBuildingId();

    final response = await _supabase
        .from('authorized_apartments')
        .select('id, building_id, unit_number, residents, created_at')
        .eq('building_id', buildingId)
        .order('unit_number', ascending: true);

    return (response as List)
        .cast<Map<String, dynamic>>()
        .map(AuthorizedApartment.fromJson)
        .toList();
  }

  /// Adds or updates an authorized apartment for the admin's building.
  ///
  /// **Upsert logic:**
  /// - If no row exists for `(building_id, unit_number)`, a new row is
  ///   INSERTed with [residents] as the initial `residents` JSONB array.
  /// - If a row already exists for that unit, [residents] are *merged* into
  ///   the existing array. A resident is considered a duplicate if their
  ///   phone number (normalised) already appears in the stored array — in
  ///   that case the existing entry is kept unchanged.
  Future<void> addAuthorizedApartment({
    required String unitNumber,
    required List<Resident> residents,
  }) async {
    final buildingId = await _resolveAdminBuildingId();

    final cleanedUnit = unitNumber.trim();

    // Deduplicate within this call by phone.
    final seen = <String>{};
    final cleanedResidents = residents
        .where((r) => r.phone.trim().isNotEmpty && seen.add(r.phone.trim()))
        .map((r) => Resident(name: r.name.trim(), phone: r.phone.trim()))
        .toList();

    // Check whether a row already exists for this (building, unit) pair.
    final existing = await _supabase
        .from('authorized_apartments')
        .select('id, residents')
        .eq('building_id', buildingId)
        .eq('unit_number', cleanedUnit)
        .maybeSingle();

    if (existing == null) {
      // No row yet — INSERT a new one.
      await _supabase.from('authorized_apartments').insert({
        'building_id': buildingId,
        'unit_number': cleanedUnit,
        'residents': cleanedResidents.map((r) => r.toJson()).toList(),
      });
    } else {
      // Row exists — merge new residents in, skipping any whose phone already
      // appears in the stored array.
      final id = existing['id'] as String;
      final raw = existing['residents'];
      final existingResidents = <Resident>[];
      if (raw is List) {
        for (final r in raw) {
          if (r is Map<String, dynamic>) {
            final phone = (r['phone'] as String?) ?? '';
            if (phone.isNotEmpty) existingResidents.add(Resident.fromJson(r));
          }
        }
      }

      final existingPhones = existingResidents.map((r) => r.phone).toSet();
      final newResidents = cleanedResidents
          .where((r) => !existingPhones.contains(r.phone))
          .toList();

      final merged = [...existingResidents, ...newResidents];

      await _supabase
          .from('authorized_apartments')
          .update({'residents': merged.map((r) => r.toJson()).toList()})
          .eq('id', id);
    }
  }

  /// Replaces the residents array for an existing authorized_apartment row.
  ///
  /// Used by the admin UI when editing an apartment to add/remove residents.
  Future<void> updateAuthorizedApartmentResidents({
    required String id,
    required List<Resident> residents,
  }) async {
    // Verify admin status before update (RLS also enforces this server-side).
    await _resolveAdminBuildingId();

    // Deduplicate by phone before writing.
    final seen = <String>{};
    final cleaned = residents
        .where((r) => r.phone.trim().isNotEmpty && seen.add(r.phone.trim()))
        .map((r) => Resident(name: r.name.trim(), phone: r.phone.trim()))
        .toList();

    await _supabase
        .from('authorized_apartments')
        .update({'residents': cleaned.map((r) => r.toJson()).toList()})
        .eq('id', id);
  }

  /// Deletes an authorized_apartment row by its UUID.
  Future<void> deleteAuthorizedApartment(String id) async {
    // Verify admin status before deletion (RLS also enforces this server-side).
    await _resolveAdminBuildingId();

    await _supabase.from('authorized_apartments').delete().eq('id', id);
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
