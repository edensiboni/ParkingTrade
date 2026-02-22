import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google OAuth. On web, redirects to Google then back to app origin; session is restored when the app loads at the redirect URL.
  Future<void> signInWithGoogle() async {
    try {
      final redirectTo = kIsWeb ? Uri.base.origin : null;
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
    } on AuthException catch (e) {
      if (e.message.contains('provider is not enabled') ||
          e.statusCode == '400' ||
          e.code == 'validation_failed') {
        throw Exception(
          'Google sign-in is not set up for this app. '
          'Please enable the Google provider in the Supabase project (Authentication → Providers).',
        );
      }
      throw Exception(
        e.message.isNotEmpty ? e.message : 'Google sign-in failed. Please try again.',
      );
    } catch (e) {
      throw Exception('Google sign-in failed: ${e.toString()}');
    }
  }

  // Send OTP to phone number
  Future<void> signInWithPhone(String phone) async {
    // Ensure phone is trimmed and in E.164 format
    final trimmedPhone = phone.trim();
    if (!trimmedPhone.startsWith('+')) {
      throw Exception('Phone number must be in E.164 format (start with +)');
    }
    
    try {
      await _supabase.auth.signInWithOtp(
        phone: trimmedPhone,
      );
    } on AuthException catch (e) {
      // Provide more specific error messages
      if (e.message.contains('Invalid phone number') || 
          e.message.contains('phone')) {
        throw Exception('Invalid phone number format. Please use E.164 format: +1234567890');
      }
      if (e.message.contains('sms_send_failed') || 
          e.message.contains('Twilio') ||
          e.message.contains('SMS')) {
        throw Exception('Failed to send SMS. Please check your phone number and try again.');
      }
      // Re-throw with a cleaner message
      throw Exception(e.message.isNotEmpty ? e.message : 'Failed to send OTP. Please try again.');
    } catch (e) {
      // Handle other exceptions
      throw Exception('Failed to send OTP: ${e.toString()}');
    }
  }

  // Verify OTP
  Future<AuthResponse> verifyOtp(String phone, String token) async {
    // Ensure phone is trimmed
    final trimmedPhone = phone.trim();
    
    try {
      return await _supabase.auth.verifyOTP(
        phone: trimmedPhone,
        token: token.trim(),
        type: OtpType.sms,
      );
    } on AuthException catch (e) {
      // Provide more specific error messages
      if (e.message.contains('Invalid') || e.message.contains('expired')) {
        throw Exception('Invalid or expired OTP. Please try again.');
      }
      if (e.message.contains('phone')) {
        throw Exception('Phone number mismatch. Please request a new OTP.');
      }
      // Re-throw with a cleaner message
      throw Exception(e.message.isNotEmpty ? e.message : 'Failed to verify OTP. Please try again.');
    } catch (e) {
      // Handle other exceptions
      throw Exception('Failed to verify OTP: ${e.toString()}');
    }
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

