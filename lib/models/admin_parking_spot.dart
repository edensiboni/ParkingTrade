/// A parking spot as seen by the admin dashboard's Spot Management tab.
///
/// Backed by the `admin_list_building_spots()` RPC (migration 042), which
/// returns every `parking_spots` row in the admin's building — including
/// `apartment_id IS NULL` orphans that the table's RLS hides — each annotated
/// with diagnostics the plain `parking_spots` row does not carry.
class AdminParkingSpot {
  final String id;
  final String spotIdentifier;
  final String buildingId;

  /// Owning apartment, or null for an orphaned spot.
  final String? apartmentId;

  /// Human-readable unit number of the owning apartment, or null when orphaned.
  final String? apartmentIdentifier;

  final bool isActive;
  final DateTime createdAt;

  /// Whether [spotIdentifier] is still listed in the owning apartment's
  /// `authorized_apartments.parking_spot_identifiers` snapshot.
  final bool inAuthorizedSnapshot;

  final int availabilityPeriodsCount;

  /// Pending + approved bookings whose `end_time` is still in the future.
  final int activeBookingsCount;

  /// True when the spot has no apartment, or its identifier has fallen out of
  /// the apartment's snapshot. These are the rows the admin needs to reconcile.
  final bool isOrphan;

  const AdminParkingSpot({
    required this.id,
    required this.spotIdentifier,
    required this.buildingId,
    required this.apartmentId,
    required this.apartmentIdentifier,
    required this.isActive,
    required this.createdAt,
    required this.inAuthorizedSnapshot,
    required this.availabilityPeriodsCount,
    required this.activeBookingsCount,
    required this.isOrphan,
  });

  factory AdminParkingSpot.fromJson(Map<String, dynamic> json) {
    return AdminParkingSpot(
      id: json['id'] as String,
      spotIdentifier: json['spot_identifier'] as String,
      buildingId: json['building_id'] as String,
      apartmentId: json['apartment_id'] as String?,
      apartmentIdentifier: json['apartment_identifier'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      inAuthorizedSnapshot: json['in_authorized_snapshot'] as bool? ?? false,
      availabilityPeriodsCount:
          (json['availability_periods_count'] as num?)?.toInt() ?? 0,
      activeBookingsCount: (json['active_bookings_count'] as num?)?.toInt() ?? 0,
      isOrphan: json['is_orphan'] as bool? ?? false,
    );
  }

  /// Whether deleting this spot would take active bookings down with it.
  bool get hasActiveBookings => activeBookingsCount > 0;
}
