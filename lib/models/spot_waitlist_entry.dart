enum WaitlistStatus {
  waiting,
  matched,
  expired,
  cancelled;

  static WaitlistStatus fromString(String value) {
    return WaitlistStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => WaitlistStatus.waiting,
    );
  }

  @override
  String toString() => name;
}

class SpotWaitlistEntry {
  final String id;
  final String spotId;
  final String requesterApartmentId;
  final String? createdByProfileId;
  final DateTime desiredStart;
  final DateTime desiredEnd;
  final WaitlistStatus status;
  final DateTime? matchedAt;
  final DateTime createdAt;

  /// Joined spot identifier (e.g. "12A"), present when the query selects
  /// `parking_spots(spot_identifier)`.
  final String? spotIdentifier;

  SpotWaitlistEntry({
    required this.id,
    required this.spotId,
    required this.requesterApartmentId,
    this.createdByProfileId,
    required this.desiredStart,
    required this.desiredEnd,
    required this.status,
    this.matchedAt,
    required this.createdAt,
    this.spotIdentifier,
  });

  factory SpotWaitlistEntry.fromJson(Map<String, dynamic> json) {
    final spotJoin = json['parking_spots'];
    return SpotWaitlistEntry(
      id: json['id'] as String,
      spotId: json['spot_id'] as String,
      requesterApartmentId: json['requester_apartment_id'] as String,
      createdByProfileId: json['created_by_profile_id'] as String?,
      desiredStart: DateTime.parse(json['desired_start'] as String),
      desiredEnd: DateTime.parse(json['desired_end'] as String),
      status: WaitlistStatus.fromString(json['status'] as String),
      matchedAt: json['matched_at'] != null
          ? DateTime.parse(json['matched_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      spotIdentifier: spotJoin is Map<String, dynamic>
          ? spotJoin['spot_identifier'] as String?
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'spot_id': spotId,
      'requester_apartment_id': requesterApartmentId,
      if (createdByProfileId != null)
        'created_by_profile_id': createdByProfileId,
      'desired_start': desiredStart.toIso8601String(),
      'desired_end': desiredEnd.toIso8601String(),
      'status': status.toString(),
      if (matchedAt != null) 'matched_at': matchedAt!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
