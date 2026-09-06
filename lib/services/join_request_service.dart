import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/building_join_request.dart';

/// What happened when a user submitted a join request.
enum JoinRequestOutcome {
  /// A request is now pending admin review.
  pending,

  /// The user turned out to be pre-authorised and was linked to their
  /// apartment immediately — they should proceed straight into the app.
  linked,

  /// The user is already an approved member of this building.
  alreadyMember,
}

class JoinRequestSubmitResult {
  final JoinRequestOutcome outcome;
  final BuildingJoinRequest? request;
  final String? buildingName;

  JoinRequestSubmitResult(this.outcome, {this.request, this.buildingName});
}

/// Resident-facing operations on `building_join_requests`.
///
/// Submission goes through the `submit-join-request` edge function (the table
/// has no INSERT policy on purpose — the function also notifies building
/// admins). Reads and cancellation are plain RLS-scoped queries.
class JoinRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<JoinRequestSubmitResult> submit({
    required String inviteCode,
    required String apartmentIdentifier,
    String? displayName,
    String? note,
  }) async {
    final response = await _supabase.functions.invoke(
      'submit-join-request',
      body: {
        'invite_code': inviteCode.trim(),
        'apartment_identifier': apartmentIdentifier.trim(),
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );

    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : (response.data as Map<String, dynamic>? ?? const {});

    if (response.status != 200 && response.status != 201) {
      throw Exception(data['error'] ?? 'Failed to submit join request');
    }

    switch (data['status']) {
      case 'linked':
        return JoinRequestSubmitResult(JoinRequestOutcome.linked);
      case 'already_member':
        return JoinRequestSubmitResult(JoinRequestOutcome.alreadyMember);
      case 'pending':
      default:
        final req = data['request'];
        final building = data['building'];
        return JoinRequestSubmitResult(
          JoinRequestOutcome.pending,
          request: req is Map<String, dynamic>
              ? BuildingJoinRequest.fromJson(req)
              : null,
          buildingName:
              building is Map<String, dynamic> ? building['name'] as String? : null,
        );
    }
  }

  /// The caller's most recent join request (any status), or null.
  Future<BuildingJoinRequest?> myLatestRequest() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final rows = await _supabase
        .from('building_join_requests')
        .select('*, buildings(name)')
        .eq('requested_by_user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1);

    final list = rows as List;
    if (list.isEmpty) return null;
    return BuildingJoinRequest.fromJson(list.first as Map<String, dynamic>);
  }

  /// Withdraw a still-pending request (RLS allows the applicant to move their
  /// own pending row to `cancelled` and nothing else).
  Future<void> cancel(String id) async {
    await _supabase
        .from('building_join_requests')
        .update({'status': 'cancelled'}).eq('id', id);
  }
}
