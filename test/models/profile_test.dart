import 'package:flutter_test/flutter_test.dart';
import 'package:parking_trade/models/profile.dart';

void main() {
  group('Profile', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 'user-1',
        'building_id': 'bldg-1',
        'status': 'approved',
        'role': 'admin',
        'display_name': 'Alice',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-02T00:00:00Z',
      };

      final profile = Profile.fromJson(json);
      expect(profile.id, 'user-1');
      expect(profile.buildingId, 'bldg-1');
      expect(profile.status, ProfileStatus.approved);
      expect(profile.role, 'admin');
      expect(profile.isAdmin, true);
      expect(profile.displayName, 'Alice');
    });

    test('fromJson defaults role to member when missing', () {
      final json = {
        'id': 'user-2',
        'building_id': null,
        'status': 'pending',
        'display_name': null,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final profile = Profile.fromJson(json);
      expect(profile.role, 'member');
      expect(profile.isAdmin, false);
    });

    test('toJson roundtrip', () {
      final profile = Profile(
        id: 'u1',
        buildingId: 'b1',
        status: ProfileStatus.approved,
        role: 'admin',
        displayName: 'Bob',
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 2),
      );

      final json = profile.toJson();
      expect(json['role'], 'admin');
      expect(json['status'], 'approved');
    });
  });

  group('ProfileStatus', () {
    test('fromString parses all values', () {
      expect(ProfileStatus.fromString('pending'), ProfileStatus.pending);
      expect(ProfileStatus.fromString('approved'), ProfileStatus.approved);
      expect(ProfileStatus.fromString('rejected'), ProfileStatus.rejected);
    });

    test('fromString throws on invalid value', () {
      expect(() => ProfileStatus.fromString('unknown'), throwsArgumentError);
    });

    test('toString returns correct string', () {
      expect(ProfileStatus.pending.toString(), 'pending');
      expect(ProfileStatus.approved.toString(), 'approved');
      expect(ProfileStatus.rejected.toString(), 'rejected');
    });
  });
}
