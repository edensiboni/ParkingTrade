class Profile {
  final String id;
  final String? buildingId;
  final ProfileStatus status;
  final String? displayName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    this.buildingId,
    required this.status,
    this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      buildingId: json['building_id'] as String?,
      status: ProfileStatus.fromString(json['status'] as String),
      displayName: json['display_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'building_id': buildingId,
      'status': status.toString(),
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

enum ProfileStatus {
  pending,
  approved,
  rejected;

  static ProfileStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return ProfileStatus.pending;
      case 'approved':
        return ProfileStatus.approved;
      case 'rejected':
        return ProfileStatus.rejected;
      default:
        throw ArgumentError('Invalid profile status: $value');
    }
  }

  @override
  String toString() {
    switch (this) {
      case ProfileStatus.pending:
        return 'pending';
      case ProfileStatus.approved:
        return 'approved';
      case ProfileStatus.rejected:
        return 'rejected';
    }
  }
}

