import 'package:flutter_test/flutter_test.dart';
import 'package:parking_trade/models/booking_request.dart';

void main() {
  group('BookingRequest', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'br-1',
        'spot_id': 'sp-1',
        'borrower_id': 'u-1',
        'lender_id': 'u-2',
        'start_time': '2025-06-01T10:00:00Z',
        'end_time': '2025-06-01T12:00:00Z',
        'status': 'approved',
        'created_at': '2025-05-01T00:00:00Z',
        'updated_at': '2025-05-02T00:00:00Z',
      };

      final booking = BookingRequest.fromJson(json);
      expect(booking.id, 'br-1');
      expect(booking.spotId, 'sp-1');
      expect(booking.status, BookingStatus.approved);
      expect(booking.startTime.isUtc, true);
    });

    test('toJson roundtrip preserves data', () {
      final booking = BookingRequest(
        id: 'x',
        spotId: 'y',
        borrowerId: 'a',
        lenderId: 'b',
        startTime: DateTime.utc(2025, 6, 1, 10),
        endTime: DateTime.utc(2025, 6, 1, 12),
        status: BookingStatus.pending,
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 1),
      );

      final json = booking.toJson();
      final restored = BookingRequest.fromJson(json);
      expect(restored.id, booking.id);
      expect(restored.status, booking.status);
    });
  });

  group('BookingStatus', () {
    test('fromString handles all values', () {
      for (final status in BookingStatus.values) {
        expect(BookingStatus.fromString(status.toString()), status);
      }
    });

    test('fromString throws on unknown', () {
      expect(() => BookingStatus.fromString('unknown'), throwsArgumentError);
    });
  });
}
