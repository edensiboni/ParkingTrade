class ParkingSpot {
  final String id;
  /// The apartment that owns this spot (replaces [residentId]).
  final String apartmentId;
  final String buildingId;
  final String spotIdentifier;
  final bool isActive;
  final DateTime createdAt;

  ParkingSpot({
    required this.id,
    required this.apartmentId,
    required this.buildingId,
    required this.spotIdentifier,
    required this.isActive,
    required this.createdAt,
  });

  factory ParkingSpot.fromJson(Map<String, dynamic> json) {
    return ParkingSpot(
      id: json['id'] as String,
      // apartment_id is the new FK; fall back to empty string if row not yet migrated
      apartmentId: (json['apartment_id'] as String?) ?? '',
      buildingId: json['building_id'] as String,
      spotIdentifier: json['spot_identifier'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'apartment_id': apartmentId,
      'building_id': buildingId,
      'spot_identifier': spotIdentifier,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ParkingSpot copyWith({
    String? apartmentId,
    bool? isActive,
  }) {
    return ParkingSpot(
      id: id,
      apartmentId: apartmentId ?? this.apartmentId,
      buildingId: buildingId,
      spotIdentifier: spotIdentifier,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
