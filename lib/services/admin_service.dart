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
  /// Each row carries a *list* of authorised resident phones (one apartment
  /// can have multiple residents — spouses, roommates, etc.). See migration
  /// 018 for the schema move from `resident_phone TEXT` →
  /// `resident_phones TEXT[]`.
  Future<List<AuthorizedApartment>> getAuthorizedApartments() async {
    final buildingId = await _resolveAdminBuildingId();

    final response = await _supabase
        .from('authorized_apartments')
        .select('id, building_id, unit_number, resident_phones, created_at')
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
  ///   INSERTed with [phones] as the initial `resident_phones` array.
  /// - If a row already exists for that unit, [phones] are *appended* to
  ///   the existing `resident_phones` array (duplicates are silently ignored).
  ///
  /// [phones] is a list of E.164 phone numbers (already normalised). Pass
  /// every resident who should be allowed to register against this unit.
  Future<void> addAuthorizedApartment({
    required String unitNumber,
    required List<String> phones,
  }) async {
    final buildingId = await _resolveAdminBuildingId();

    final cleanedUnit = unitNumber.trim();
    final cleanedPhones = phones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toSet() // de-duplicate within this call
        .toList();

    // Check whether a row already exists for this (building, unit) pair.
    final existing = await _supabase
        .from('authorized_apartments')
        .select('id, resident_phones')
        .eq('building_id', buildingId)
        .eq('unit_number', cleanedUnit)
        .maybeSingle();

    if (existing == null) {
      // No row yet — INSERT a new one.
      await _supabase.from('authorized_apartments').insert({
        'building_id': buildingId,
        'unit_number': cleanedUnit,
        'resident_phones': cleanedPhones,
      });
    } else {
      // Row exists — merge the new phones into the existing array,
      // avoiding duplicates.
      final id = existing['id'] as String;
      final raw = existing['resident_phones'];
      final existingPhones = <String>[];
      if (raw is List) {
        for (final p in raw) {
          if (p is String && p.isNotEmpty) existingPhones.add(p);
        }
      }

      final mergedPhones = {
        ...existingPhones,
        ...cleanedPhones,
      }.toList();

      await _supabase
          .from('authorized_apartments')
          .update({'resident_phones': mergedPhones})
          .eq('id', id);
    }
  }

  /// Replaces the resident phones array for an existing authorized_apartment row.
  ///
  /// Used by the admin UI when editing an apartment to add/remove phones.
  Future<void> updateAuthorizedApartmentPhones({
    required String id,
    required List<String> phones,
  }) async {
    // Verify admin status before update (RLS also enforces this server-side).
    await _resolveAdminBuildingId();

    final cleanedPhones = phones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    await _supabase
        .from('authorized_apartments')
        .update({'resident_phones': cleanedPhones})
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
