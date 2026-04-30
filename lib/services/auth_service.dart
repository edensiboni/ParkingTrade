import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  /// Returns the current session, or null if no valid session exists.
  Session? get currentSession => _supabase.auth.currentSession;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google OAuth.
  ///
  /// On **web** we use the PKCE flow (`AuthFlowType.pkce`) so that Supabase
  /// stores a code-verifier in `localStorage` before redirecting to Google.
  /// When Google redirects back with `?code=…`, the Supabase SDK reads the
  /// verifier from storage and exchanges the code for a session automatically.
  /// This eliminates the "Code verifier could not be found in local storage"
  /// error that occurs with the default implicit (fragment-hash) flow when the
  /// page is hard-reloaded on the callback URL.
  ///
  /// On **mobile** no `redirectTo` or flow override is needed — the SDK uses
  /// deep links instead.
  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Redirect back to the exact origin.  This must match one of the
        // Redirect URLs configured in Supabase Dashboard →
        // Authentication → URL Configuration.
        final redirectTo = '${Uri.base.origin}/';
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectTo,
        );
      } else {
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
        );
      }
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

  /// Dev-only: sign in with a shadow email/password account.
  ///
  /// [shadowEmail] — e.g. dev_<digits>@parking.test
  /// [password]    — the password set on that Supabase Auth account.
  ///
  /// This method is intentionally NOT gated by kDebugMode so it compiles in
  /// release; the caller (PhoneAuthScreen) gates the UI with kDebugMode, which
  /// the Dart compiler tree-shakes in release mode.
  Future<AuthResponse> devImpersonate({
    required String shadowEmail,
    required String password,
  }) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: shadowEmail,
        password: password,
      );
    } on AuthException catch (e) {
      // Shadow user is missing (deleted from Supabase) — auto-create it and retry.
      final isInvalidCredentials = e.message.toLowerCase().contains('invalid') ||
          e.message.toLowerCase().contains('credentials') ||
          e.message.toLowerCase().contains('not found') ||
          e.statusCode == '400';

      if (isInvalidCredentials) {
        print('Shadow user not found, creating new one...');
        try {
          await _supabase.auth.signUp(
            email: shadowEmail,
            password: password,
          );
          print('Shadow user created: $shadowEmail — retrying sign-in...');
          await Future.delayed(const Duration(seconds: 1));
          return await _supabase.auth.signInWithPassword(
            email: shadowEmail,
            password: password,
          );
        } on AuthException catch (signUpError) {
          throw Exception(
            'Dev login failed (auto-create also failed): ${signUpError.message}',
          );
        } catch (signUpError) {
          throw Exception('Dev login failed (auto-create also failed): $signUpError');
        }
      }

      throw Exception(
        e.message.isNotEmpty
            ? 'Dev login failed: ${e.message}'
            : 'Dev login failed. Check that the shadow account exists in Supabase Auth.',
      );
    } catch (e) {
      throw Exception('Dev login failed: $e');
    }
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

  // Get current user profile.
  //
  // When no profile row is found by user.id, we attempt a phone-based
  // linking pass (calling the link_profile_by_phone RPC) so that users
  // who authenticated before migration 020 was deployed — or whose first
  // OTP login created an auth.users row before the trigger matched — can
  // still be linked to their pre-authorised apartment without having to
  // sign out and back in.
  Future<Profile?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) return Profile.fromJson(response);

      // No profile found by id — try to link via phone.
      await _tryLinkProfileByPhone(user);

      // Re-query after the linking attempt.
      final retried = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (retried == null) return null;
      return Profile.fromJson(retried);
    } catch (e) {
      // If profile doesn't exist or there's an error, return null
      // Return null so the app routes to the not-registered screen
      return null;
    }
  }

  /// Attempts to link the current auth user to a pre-created profile (or
  /// auto-create one) by calling the `link_profile_by_phone` database
  /// function.  Silently ignores errors — the caller will simply route to
  /// the not-registered screen if linking fails.
  Future<void> _tryLinkProfileByPhone(User user) async {
    final phone = user.phone;
    if (phone == null || phone.isEmpty) return;

    try {
      // The RPC mirrors the trigger logic: it normalises the phone, searches
      // profiles.phone and then authorized_apartments.residents, and creates /
      // links the profile when a match is found.
      await _supabase.rpc('link_profile_by_phone', params: {
        'p_user_id': user.id,
        'p_phone': normalisePhone(phone),
      });
    } catch (e) {
      debugPrint('_tryLinkProfileByPhone: $e');
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

  /// After a Google sign-in, if the profile's [display_name] is missing or
  /// still the placeholder "Unnamed resident", replace it with the name that
  /// Google provided in [user.userMetadata].
  ///
  /// Safe to call on every sign-in — it is a no-op when the name is already
  /// set to something meaningful.
  Future<void> syncGoogleDisplayName() async {
    final user = currentUser;
    if (user == null || !isGoogleUser) return;

    final googleName = (user.userMetadata?['full_name'] as String?)?.trim();
    if (googleName == null || googleName.isEmpty) return;

    try {
      final response = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) return;

      final existing = (response['display_name'] as String?)?.trim();
      final needsUpdate =
          existing == null || existing.isEmpty || existing == 'Unnamed resident';

      if (needsUpdate) {
        await _supabase
            .from('profiles')
            .update({'display_name': googleName})
            .eq('id', user.id);
      }
    } catch (e) {
      // Non-fatal — the name will be updated on the next sign-in.
      debugPrint('syncGoogleDisplayName: $e');
    }
  }
}

