/// Represents a row in the `authorized_apartments` table.
///
/// Each row authorises a list of resident phone numbers (E.164) for a
/// specific apartment unit in a building. The row is the canonical
/// allow-list used at OTP login time — a phone is recognised only if
/// it appears inside [residentPhones].
///
/// Note: The Supabase column is `resident_phones text[]` (migration 018,
/// which replaced the legacy scalar `resident_phone text` column).
class AuthorizedApartment {
  final String id;
  final String buildingId;
  final String unitNumber;
  final List<String> residentPhones;
  final DateTime createdAt;

  AuthorizedApartment({
    required this.id,
    required this.buildingId,
    required this.unitNumber,
    required this.residentPhones,
    required this.createdAt,
  });

  factory AuthorizedApartment.fromJson(Map<String, dynamic> json) {
    final raw = json['resident_phones'];
    final phones = <String>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is String && p.isNotEmpty) phones.add(p);
      }
    }

    return AuthorizedApartment(
      id: json['id'] as String,
      buildingId: (json['building_id'] as String?) ?? '',
      unitNumber: json['unit_number'] as String,
      residentPhones: phones,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'building_id': buildingId,
      'unit_number': unitNumber,
      'resident_phones': residentPhones,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AuthorizedApartment copyWith({
    String? id,
    String? buildingId,
    String? unitNumber,
    List<String>? residentPhones,
    DateTime? createdAt,
  }) {
    return AuthorizedApartment(
      id: id ?? this.id,
      buildingId: buildingId ?? this.buildingId,
      unitNumber: unitNumber ?? this.unitNumber,
      residentPhones: residentPhones ?? this.residentPhones,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'AuthorizedApartment($unitNumber, ${residentPhones.length} phones)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthorizedApartment && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
