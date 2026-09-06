/// A building-wide announcement posted by an admin (Roadmap Phase 4).
///
/// Backed by the `building_announcements` table. Readable by any approved
/// member of the building (RLS), written only through the
/// `create_building_announcement` RPC. Immutable in v1.
class BuildingAnnouncement {
  final String id;
  final String buildingId;

  /// The admin who posted it, or null if that profile was later removed.
  final String? adminId;

  final String title;
  final String body;
  final DateTime createdAt;

  const BuildingAnnouncement({
    required this.id,
    required this.buildingId,
    required this.adminId,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory BuildingAnnouncement.fromJson(Map<String, dynamic> json) {
    return BuildingAnnouncement(
      id: json['id'] as String,
      buildingId: json['building_id'] as String,
      adminId: json['admin_id'] as String?,
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
