class Apartment {
  final String id;
  final String buildingId;
  final String identifier;
  final DateTime createdAt;

  Apartment({
    required this.id,
    required this.buildingId,
    required this.identifier,
    required this.createdAt,
  });

  factory Apartment.fromJson(Map<String, dynamic> json) {
    return Apartment(
      id: json['id'] as String,
      buildingId: json['building_id'] as String,
      identifier: json['identifier'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'building_id': buildingId,
      'identifier': identifier,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'Apartment($identifier, building: $buildingId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Apartment && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
