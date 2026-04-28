/// A single resident entry stored inside the `residents` JSONB array on
/// the `authorized_apartments` table (migration 019).
///
/// Example JSON: {"name": "Alice", "phone": "+972501234567"}
class Resident {
  /// Display name for the resident (may be empty string if not set).
  final String name;

  /// E.164-formatted phone number. This is the field used for RLS lookups.
  final String phone;

  const Resident({required this.name, required this.phone});

  factory Resident.fromJson(Map<String, dynamic> json) {
    return Resident(
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  /// Returns a human-readable label: "Name (Phone)" when a name is present,
  /// or just the phone number otherwise.
  String get displayLabel =>
      name.trim().isNotEmpty ? '${name.trim()} ($phone)' : phone;

  @override
  String toString() => displayLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Resident && other.phone == phone && other.name == name);

  @override
  int get hashCode => Object.hash(name, phone);
}

// ─────────────────────────────────────────────────────────────────────────────

/// Represents a row in the `authorized_apartments` table.
///
/// Each row authorises a list of residents (each with a name and phone number)
/// for a specific apartment unit in a building. The row is the canonical
/// allow-list used at OTP login time — a phone is recognised only if it
/// appears inside [residents].
///
/// Note: The Supabase column is `residents JSONB` (migration 019, which
/// replaced the legacy `resident_phones TEXT[]` column from migration 018).
class AuthorizedApartment {
  final String id;
  final String buildingId;
  final String unitNumber;
  final List<Resident> residents;
  final DateTime createdAt;

  AuthorizedApartment({
    required this.id,
    required this.buildingId,
    required this.unitNumber,
    required this.residents,
    required this.createdAt,
  });

  factory AuthorizedApartment.fromJson(Map<String, dynamic> json) {
    final raw = json['residents'];
    final residents = <Resident>[];
    if (raw is List) {
      for (final r in raw) {
        if (r is Map<String, dynamic>) {
          final phone = (r['phone'] as String?) ?? '';
          if (phone.isNotEmpty) residents.add(Resident.fromJson(r));
        }
      }
    }

    return AuthorizedApartment(
      id: json['id'] as String,
      buildingId: (json['building_id'] as String?) ?? '',
      unitNumber: json['unit_number'] as String,
      residents: residents,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'building_id': buildingId,
      'unit_number': unitNumber,
      'residents': residents.map((r) => r.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  AuthorizedApartment copyWith({
    String? id,
    String? buildingId,
    String? unitNumber,
    List<Resident>? residents,
    DateTime? createdAt,
  }) {
    return AuthorizedApartment(
      id: id ?? this.id,
      buildingId: buildingId ?? this.buildingId,
      unitNumber: unitNumber ?? this.unitNumber,
      residents: residents ?? this.residents,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'AuthorizedApartment($unitNumber, ${residents.length} residents)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthorizedApartment && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
