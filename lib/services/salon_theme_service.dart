import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/salon_theme_config.dart';
import 'building_service.dart';

/// Loads per-salon branding from Supabase.
///
/// Primary source: `salons` table. If that row is missing (or the table is not
/// deployed yet), falls back to `buildings` so existing building UUIDs in QR
/// links still resolve to a named experience with the neutral palette.
class SalonThemeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final BuildingService _buildingService = BuildingService();

  Future<SalonThemeConfig?> fetchSalonTheme(String salonId) async {
    try {
      final salonRow = await _supabase
          .from('salons')
          .select('name, primary_color, secondary_color, logo_url')
          .eq('id', salonId)
          .maybeSingle();

      if (salonRow != null) {
        return SalonThemeConfig.fromJson(salonId, salonRow);
      }
    } catch (_) {
      // Table may not exist yet — try buildings below.
    }

    try {
      final building = await _buildingService.getBuildingById(salonId);
      if (building == null) return null;
      return SalonThemeConfig(
        salonId: salonId,
        name: building.name,
      );
    } catch (_) {
      return null;
    }
  }
}
