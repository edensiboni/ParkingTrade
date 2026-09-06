import 'package:flutter_test/flutter_test.dart';
import 'package:parking_trade/models/building_announcement.dart';

void main() {
  group('BuildingAnnouncement', () {
    test('fromJson parses all fields', () {
      final a = BuildingAnnouncement.fromJson({
        'id': 'ann-1',
        'building_id': 'bldg-1',
        'admin_id': 'admin-1',
        'title': 'Water shutoff',
        'body': 'Tuesday 9-11am.',
        'created_at': '2026-09-06T08:00:00Z',
      });

      expect(a.id, 'ann-1');
      expect(a.buildingId, 'bldg-1');
      expect(a.adminId, 'admin-1');
      expect(a.title, 'Water shutoff');
      expect(a.body, 'Tuesday 9-11am.');
      expect(a.createdAt, DateTime.utc(2026, 9, 6, 8));
    });

    test('fromJson tolerates a null admin_id (admin profile later removed)', () {
      final a = BuildingAnnouncement.fromJson({
        'id': 'ann-2',
        'building_id': 'bldg-1',
        'admin_id': null,
        'title': 'Notice',
        'body': 'Body.',
        'created_at': '2026-09-06T10:30:00Z',
      });

      expect(a.adminId, isNull);
      expect(a.title, 'Notice');
    });
  });
}
