import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

/// A profile enriched with the user's phone number (sourced from Supabase Auth
/// metadata via the `profiles` view / RPC). Phone is nullable because it may
/// not be available to the apartment admin via RLS.
class ApartmentProfile {
  final Profile profile;
  final String? phone;

  const ApartmentProfile({required this.profile, this.phone});

  String get displayIdentifier {
    if (profile.displayName != null && profile.displayName!.trim().isNotEmpty) {
      return profile.displayName!.trim();
    }
    if (phone != null && phone!.isNotEmpty) return phone!;
    return 'Resident';
  }
}

class ApartmentService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all profiles belonging to the same apartment as the current user.
  /// Each profile is enriched with the phone number from the `profiles` table
  /// (stored via the `phone` column that is populated on sign-up).
  Future<List<ApartmentProfile>> getApartmentProfiles() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Get current user's apartment_id and verify they are an apartment admin.
    final currentRow = await _supabase
        .from('profiles')
        .select('apartment_id, is_apartment_admin')
        .eq('id', user.id)
        .single();

    final apartmentId = currentRow['apartment_id'] as String?;
    if (apartmentId == null) throw Exception('You are not assigned to an apartment.');

    final isApartmentAdmin = (currentRow['is_apartment_admin'] as bool?) ?? false;
    if (!isApartmentAdmin) {
      throw Exception('Only apartment admins can view apartment members.');
    }

    // Fetch all profiles in the same apartment, including phone if available.
    final response = await _supabase
        .from('profiles')
        .select()
        .eq('apartment_id', apartmentId)
        .order('created_at', ascending: true);

    return (response as List).map((json) {
      final profile = Profile.fromJson(json);
      final phone = json['phone'] as String?;
      return ApartmentProfile(profile: profile, phone: phone);
    }).toList();
  }

  /// Update the notification preferences for a specific profile.
  ///
  /// [profileId] — the ID of the profile to update.
  /// [receivesPush] — if non-null, sets `receives_push_notifications`.
  /// [receivesChat] — if non-null, sets `receives_chat_notifications`.
  Future<void> updateNotificationPreferences({
    required String profileId,
    bool? receivesPush,
    bool? receivesChat,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    if (receivesPush == null && receivesChat == null) return;

    // Verify the caller is an apartment admin in the same apartment as the
    // target profile before making the update.
    final rows = await _supabase
        .from('profiles')
        .select('apartment_id, is_apartment_admin')
        .eq('id', user.id)
        .single();

    final callerApartmentId = rows['apartment_id'] as String?;
    final isApartmentAdmin = (rows['is_apartment_admin'] as bool?) ?? false;

    if (!isApartmentAdmin || callerApartmentId == null) {
      throw Exception('Only apartment admins can update notification settings.');
    }

    // Confirm the target profile belongs to the same apartment.
    final targetRow = await _supabase
        .from('profiles')
        .select('apartment_id')
        .eq('id', profileId)
        .single();

    if (targetRow['apartment_id'] != callerApartmentId) {
      throw Exception('Profile does not belong to your apartment.');
    }

    final updates = <String, dynamic>{};
    if (receivesPush != null) {
      updates['receives_push_notifications'] = receivesPush;
    }
    if (receivesChat != null) {
      updates['receives_chat_notifications'] = receivesChat;
    }

    await _supabase
        .from('profiles')
        .update(updates)
        .eq('id', profileId);
  }
}
