import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  /// Returns the current session, or null if no valid session exists.
  Session? get currentSession => _supabase.auth.currentSession;

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

  /// Normalises a phone number to E.164 format:
  /// 1. Strips all whitespace, dashes, dots, and parentheses.
  /// 2. Converts a leading '0' to the Israeli country code '+972'.
  static String normalisePhone(String raw) {
    // Remove everything except digits and a leading '+'.
    String cleaned = raw.trim();
    // Strip spaces, dashes, dots, parentheses
    cleaned = cleaned.replaceAll(RegExp(r'[\s\-().]+'), '');
    // Auto-convert Israeli local format: 0XX → +972XX
    if (cleaned.startsWith('0')) {
      cleaned = '+972${cleaned.substring(1)}';
    }
    return cleaned;
  }

  // Send OTP to phone number
  Future<void> signInWithPhone(String phone) async {
    final normalisedPhone = normalisePhone(phone);

    if (!normalisedPhone.startsWith('+')) {
      throw Exception(
        'Please enter your phone number starting with a country code, e.g. +972501234567',
      );
    }

    try {
      await _supabase.auth.signInWithOtp(
        phone: normalisedPhone,
      );
    } on AuthException catch (e) {
      // 400 Bad Request from Supabase → phone number rejected
      if (e.statusCode == '400' ||
          e.message.contains('Invalid phone number') ||
          e.message.contains('phone')) {
        throw Exception(
          'We couldn\'t send a code to that number. '
          'Please double-check it and try again.',
        );
      }
      if (e.message.contains('sms_send_failed') ||
          e.message.contains('Twilio') ||
          e.message.contains('SMS')) {
        throw Exception(
          'Failed to send the SMS. Please check your number and try again.',
        );
      }
      throw Exception(
        e.message.isNotEmpty ? e.message : 'Failed to send code. Please try again.',
      );
    } catch (e) {
      throw Exception('Failed to send code: ${e.toString()}');
    }
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
    // Normalise so it always matches what was sent to Supabase
    final trimmedPhone = normalisePhone(phone);
    
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
      // Return null so the app routes to the not-registered screen
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
    String? phone,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Not authenticated');

    final updates = <String, dynamic>{};
    if (displayName != null) {
      updates['display_name'] = displayName;
    }
    if (phone != null) {
      updates['phone'] = phone;
    }

    if (updates.isEmpty) return;

    await _supabase
        .from('profiles')
        .update(updates)
        .eq('id', user.id);
  }

  /// Returns true if the current user authenticated via Google OAuth
  /// (i.e. has no phone number on their auth.users row yet).
  bool get isGoogleUser {
    final user = currentUser;
    if (user == null) return false;
    return user.appMetadata['provider'] == 'google' ||
        (user.identities?.any((i) => i.provider == 'google') ?? false);
  }
}

