/// A self-service request from an authenticated user to join a building they
/// are not pre-authorised for. Backed by the `building_join_requests` table
/// (migration 041) and actioned through the `review-join-request` edge
/// function. See also [Profile] for the member record created on approval.
class BuildingJoinRequest {
  final String id;
  final String buildingId;
  final String requestedByUserId;
  final String phone;
  final String? displayName;
  final String apartmentIdentifier;
  final JoinRequestStatus status;
  final String? note;
  final String? reviewReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  /// Optional building name, present when the row was fetched with a
  /// `buildings(name)` join (resident-facing "pending" screen) or returned
  /// by the submit edge function.
  final String? buildingName;

  BuildingJoinRequest({
    required this.id,
    required this.buildingId,
    required this.requestedByUserId,
    required this.phone,
    this.displayName,
    required this.apartmentIdentifier,
    required this.status,
    this.note,
    this.reviewReason,
    required this.createdAt,
    this.reviewedAt,
    this.buildingName,
  });

  factory BuildingJoinRequest.fromJson(Map<String, dynamic> json) {
    // `buildings` may arrive as a nested object (PostgREST join) or be absent.
    final buildings = json['buildings'];
    final joinedName = buildings is Map<String, dynamic>
        ? buildings['name'] as String?
        : null;

    return BuildingJoinRequest(
      id: json['id'] as String,
      buildingId: json['building_id'] as String,
      requestedByUserId: json['requested_by_user_id'] as String,
      phone: json['phone'] as String? ?? '',
      displayName: json['display_name'] as String?,
      apartmentIdentifier: json['apartment_identifier'] as String? ?? '',
      status: JoinRequestStatus.fromString(json['status'] as String? ?? 'pending'),
      note: json['note'] as String?,
      reviewReason: json['review_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      buildingName: (json['building_name'] as String?) ?? joinedName,
    );
  }
}

enum JoinRequestStatus {
  pending,
  approved,
  rejected,
  cancelled;

  static JoinRequestStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return JoinRequestStatus.pending;
      case 'approved':
        return JoinRequestStatus.approved;
      case 'rejected':
        return JoinRequestStatus.rejected;
      case 'cancelled':
        return JoinRequestStatus.cancelled;
      default:
        throw ArgumentError('Invalid join request status: $value');
    }
  }

  @override
  String toString() {
    switch (this) {
      case JoinRequestStatus.pending:
        return 'pending';
      case JoinRequestStatus.approved:
        return 'approved';
      case JoinRequestStatus.rejected:
        return 'rejected';
      case JoinRequestStatus.cancelled:
        return 'cancelled';
    }
  }
}
