class Profile {
  final String id;
  /// Kept for backwards-compat during gradual migration; prefer [apartmentId].
  final String? buildingId;
  final String? apartmentId;
  final ProfileStatus status;
  final String role;
  final bool isApartmentAdmin;
  final bool receivesPushNotifications;
  final bool receivesChatNotifications;
  final String? displayName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    this.buildingId,
    this.apartmentId,
    required this.status,
    this.role = 'member',
    this.isApartmentAdmin = false,
    this.receivesPushNotifications = false,
    this.receivesChatNotifications = false,
    this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True if this profile has building-level admin privileges.
  bool get isAdmin => role == 'admin';

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      buildingId: json['building_id'] as String?,
      apartmentId: json['apartment_id'] as String?,
      status: ProfileStatus.fromString(json['status'] as String),
      role: (json['role'] as String?) ?? 'member',
      isApartmentAdmin: (json['is_apartment_admin'] as bool?) ?? false,
      receivesPushNotifications:
          (json['receives_push_notifications'] as bool?) ?? false,
      receivesChatNotifications:
          (json['receives_chat_notifications'] as bool?) ?? false,
      displayName: json['display_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (buildingId != null) 'building_id': buildingId,
      'apartment_id': apartmentId,
      'status': status.toString(),
      'role': role,
      'is_apartment_admin': isApartmentAdmin,
      'receives_push_notifications': receivesPushNotifications,
      'receives_chat_notifications': receivesChatNotifications,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Profile copyWith({
    String? apartmentId,
    ProfileStatus? status,
    String? role,
    bool? isApartmentAdmin,
    bool? receivesPushNotifications,
    bool? receivesChatNotifications,
    String? displayName,
  }) {
    return Profile(
      id: id,
      buildingId: buildingId,
      apartmentId: apartmentId ?? this.apartmentId,
      status: status ?? this.status,
      role: role ?? this.role,
      isApartmentAdmin: isApartmentAdmin ?? this.isApartmentAdmin,
      receivesPushNotifications:
          receivesPushNotifications ?? this.receivesPushNotifications,
      receivesChatNotifications:
          receivesChatNotifications ?? this.receivesChatNotifications,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
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
