import 'package:flutter_test/flutter_test.dart';
import 'package:parking_trade/models/admin_parking_spot.dart';

void main() {
  group('AdminParkingSpot', () {
    Map<String, dynamic> baseJson() => {
          'id': 'spot-1',
          'spot_identifier': 'A1',
          'apartment_id': 'apt-1',
          'apartment_identifier': '4B',
          'building_id': 'bldg-1',
          'is_active': true,
          'created_at': '2026-01-01T00:00:00Z',
          'in_authorized_snapshot': true,
          'availability_periods_count': 2,
          'active_bookings_count': 0,
          'is_orphan': false,
        };

    test('fromJson parses a healthy, assigned spot', () {
      final spot = AdminParkingSpot.fromJson(baseJson());
      expect(spot.id, 'spot-1');
      expect(spot.spotIdentifier, 'A1');
      expect(spot.apartmentId, 'apt-1');
      expect(spot.apartmentIdentifier, '4B');
      expect(spot.isActive, true);
      expect(spot.inAuthorizedSnapshot, true);
      expect(spot.availabilityPeriodsCount, 2);
      expect(spot.activeBookingsCount, 0);
      expect(spot.isOrphan, false);
      expect(spot.hasActiveBookings, false);
    });

    test('fromJson parses an orphaned spot with no apartment', () {
      final json = baseJson()
        ..['apartment_id'] = null
        ..['apartment_identifier'] = null
        ..['in_authorized_snapshot'] = false
        ..['is_orphan'] = true
        ..['active_bookings_count'] = 3;

      final spot = AdminParkingSpot.fromJson(json);
      expect(spot.apartmentId, isNull);
      expect(spot.apartmentIdentifier, isNull);
      expect(spot.isOrphan, true);
      expect(spot.hasActiveBookings, true);
      expect(spot.activeBookingsCount, 3);
    });

    test('fromJson tolerates numeric counts arriving as num and missing flags', () {
      final json = {
        'id': 'spot-2',
        'spot_identifier': 'B2',
        'apartment_id': 'apt-2',
        'apartment_identifier': '7A',
        'building_id': 'bldg-1',
        'is_active': false,
        'created_at': '2026-02-01T12:00:00Z',
        'availability_periods_count': 1.0,
        'active_bookings_count': 2.0,
      };

      final spot = AdminParkingSpot.fromJson(json);
      expect(spot.isActive, false);
      expect(spot.availabilityPeriodsCount, 1);
      expect(spot.activeBookingsCount, 2);
      expect(spot.inAuthorizedSnapshot, false);
      expect(spot.isOrphan, false);
    });
  });
}
