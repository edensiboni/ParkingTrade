class ParkingSpot {
  final String id;
  final String residentId;
  final String buildingId;
  final String spotIdentifier;
  final bool isActive;
  final DateTime createdAt;

  ParkingSpot({
    required this.id,
    required this.residentId,
    required this.buildingId,
    required this.spotIdentifier,
    required this.isActive,
    required this.createdAt,
  });

  factory ParkingSpot.fromJson(Map<String, dynamic> json) {
    return ParkingSpot(
      id: json['id'] as String,
      residentId: json['resident_id'] as String,
      buildingId: json['building_id'] as String,
      spotIdentifier: json['spot_identifier'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resident_id': residentId,
      'building_id': buildingId,
      'spot_identifier': spotIdentifier,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

