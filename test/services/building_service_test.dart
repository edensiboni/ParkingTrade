import 'package:flutter_test/flutter_test.dart';
import 'package:parking_trade/services/building_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
    );
  });

  group('BuildingService', () {
    test('createBuilding completes with UnimplementedError (use create-building-admin flow)', () {
      final service = BuildingService();
      expect(
        service.createBuilding(name: 'Test Tower'),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
