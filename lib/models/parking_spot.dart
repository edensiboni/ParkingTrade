class ParkingSpot {
  final String id;
  /// The apartment that owns this spot (replaces [residentId]).
  final String apartmentId;
  final String buildingId;
  final String spotIdentifier;
  final bool isActive;
  final DateTime createdAt;

  /// Human-readable apartment identifier (e.g. "4B", "12") populated when the
  /// query joins the `apartments` table via `.select('*, apartments(identifier)')`.
  /// Null when the spot was fetched without the join.
  final String? apartmentIdentifier;

  ParkingSpot({
    required this.id,
    required this.apartmentId,
    required this.buildingId,
    required this.spotIdentifier,
    required this.isActive,
    required this.createdAt,
    this.apartmentIdentifier,
  });

  factory ParkingSpot.fromJson(Map<String, dynamic> json) {
    // The `apartments` join is present when the query includes
    // `.select('*, apartments(identifier)')`. It may be absent for plain selects.
    final apartmentsJoin = json['apartments'] as Map<String, dynamic>?;

    return ParkingSpot(
      id: json['id'] as String,
      // apartment_id is the new FK; fall back to empty string if row not yet migrated
      apartmentId: (json['apartment_id'] as String?) ?? '',
      buildingId: json['building_id'] as String,
      spotIdentifier: json['spot_identifier'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      apartmentIdentifier: apartmentsJoin?['identifier'] as String?,
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
    String? apartmentIdentifier,
  }) {
    return ParkingSpot(
      id: id,
      apartmentId: apartmentId ?? this.apartmentId,
      buildingId: buildingId,
      spotIdentifier: spotIdentifier,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      apartmentIdentifier: apartmentIdentifier ?? this.apartmentIdentifier,
    );
  }
}
