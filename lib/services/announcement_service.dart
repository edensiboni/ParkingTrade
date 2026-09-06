import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/building_announcement.dart';

/// Building announcements (Roadmap Phase 4).
///
/// - [getBuildingAnnouncements] is used by both residents and admins — RLS
///   scopes the result to the caller's building.
/// - [sendAnnouncement] is admin-only; the `create_building_announcement`
///   RPC re-checks that server-side and enqueues the push fan-out.
class AnnouncementService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Past announcements for the current user's building, newest first.
  Future<List<BuildingAnnouncement>> getBuildingAnnouncements() async {
    final response = await _supabase
        .from('building_announcements')
        .select('id, building_id, admin_id, title, body, created_at')
        .order('created_at', ascending: false);

    return (response as List)
        .cast<Map<String, dynamic>>()
        .map(BuildingAnnouncement.fromJson)
        .toList();
  }

  /// Compose + broadcast an announcement to the whole building via the
  /// `create_building_announcement` RPC (SECURITY DEFINER, self-securing).
  /// Returns the created row; delivery happens asynchronously via the outbox.
  Future<BuildingAnnouncement> sendAnnouncement({
    required String title,
    required String body,
  }) async {
    final response = await _supabase.rpc(
      'create_building_announcement',
      params: {'p_title': title, 'p_body': body},
    );

    // A scalar-composite RETURNS: supabase-js/dart returns the row object
    // directly (or a single-element list depending on PostgREST shaping).
    final row = response is List
        ? response.first as Map<String, dynamic>
        : response as Map<String, dynamic>;
    return BuildingAnnouncement.fromJson(row);
  }
}
