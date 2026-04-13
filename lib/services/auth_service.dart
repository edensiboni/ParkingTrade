import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Send OTP to phone number
  Future<void> signInWithPhone(String phone) async {
    await _supabase.auth.signInWithOtp(
      phone: phone,
    );
  }

  // Dev/testing sign-in (email/password) to bypass OTP.
  // Only used when `DEV_AUTH_ENABLED=true`.
  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Verify OTP
  Future<AuthResponse> verifyOtp(String phone, String token) async {
    return await _supabase.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  // Get current user profile
  Future<Profile?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) return null;
      return Profile.fromJson(response);
    } catch (e) {
      // If profile doesn't exist or there's an error, return null
      // This allows new users to proceed to join-building screen
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Update profile
  Future<void> updateProfile({
    String? displayName,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Not authenticated');

    final updates = <String, dynamic>{};
    if (displayName != null) {
      updates['display_name'] = displayName;
    }

    if (updates.isEmpty) return;

    await _supabase
        .from('profiles')
        .update(updates)
        .eq('id', user.id);
  }
}

