class Building {
  final String id;
  final String name;
  final String inviteCode;
  final bool approvalRequired;
  final DateTime createdAt;

  /// Full formatted address from Google Places (optional).
  final String? address;

  /// WGS-84 latitude from geocoding (optional).
  final double? latitude;

  /// WGS-84 longitude from geocoding (optional).
  final double? longitude;

  /// Total number of parking spots in the building (optional).
  final int? totalParkingSpots;

  Building({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.approvalRequired,
    required this.createdAt,
    this.address,
    this.latitude,
    this.longitude,
    this.totalParkingSpots,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      approvalRequired: json['approval_required'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      totalParkingSpots: (json['total_parking_spots'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'invite_code': inviteCode,
      'approval_required': approvalRequired,
      'created_at': createdAt.toIso8601String(),
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (totalParkingSpots != null) 'total_parking_spots': totalParkingSpots,
    };
  }
}
