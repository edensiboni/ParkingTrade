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

  /// Strips noise characters (spaces, dashes, dots, parentheses) from a
  /// phone number. Used as the first step before deriving format variants.
  static String _stripPhoneNoise(String raw) {
    return raw.trim().replaceAll(RegExp(r'[\s\-().]+'), '');
  }

  /// Returns up to three format variations of [raw] so the tenant lookup is
  /// robust against any storage style the admin may have used in
  /// `authorized_apartments.residents`:
  ///
  ///   1. **International** (E.164 with leading `+`, e.g. `+972521234567`) —
  ///      the canonical form. Tried FIRST because it's the format the admin
  ///      UI normalises to, and the only format guaranteed to compare equal
  ///      regardless of whether the database-side `normalise_phone()` helper
  ///      is up to date (see migration 022).
  ///   2. **Local** — strict Israeli local format with a leading `0`
  ///      (e.g. `052...`), produced by stripping a leading `+972` or `972`.
  ///   3. **Raw / country-code-without-plus** (e.g. `972521234567`) — the
  ///      cleaned input as-is. Useful when the admin stored the number with
  ///      the country code but no leading `+`, which is also the form
  ///      Supabase Auth persists in `auth.users.phone`.
  ///
  /// Variations are de-duplicated and empty strings are excluded. The
  /// canonical international form is intentionally placed first so callers
  /// that stop on the first successful match (e.g. `_tryLinkProfileByPhone`)
  /// hit the most reliable format on the first try.
  ///
  /// The list is intentionally limited to Israeli (`+972` / `972` / `0`)
  /// conventions because that is the only locale the app currently targets.
  static List<String> phoneVariations(String raw) {
    final cleaned = _stripPhoneNoise(raw);
    if (cleaned.isEmpty) return const [];

    String? local;
    String? international;

    if (cleaned.startsWith('+972')) {
      // +97252... → 052...
      final rest = cleaned.substring(4);
      if (rest.isNotEmpty) local = '0$rest';
      international = cleaned;
    } else if (cleaned.startsWith('972')) {
      // 97252... → 052... and +97252...
      final rest = cleaned.substring(3);
      if (rest.isNotEmpty) local = '0$rest';
      international = '+$cleaned';
    } else if (cleaned.startsWith('0')) {
      // 052... → +97252...
      local = cleaned;
      final rest = cleaned.substring(1);
      if (rest.isNotEmpty) international = '+972$rest';
    } else if (cleaned.startsWith('+')) {
      // Non-Israeli E.164 — only the raw form is meaningful.
      international = cleaned;
    }

    // Order matters: try the canonical `+972…` form first because it is the
    // format the admin UI stores in authorized_apartments.residents, so it
    // is the most likely to produce an immediate match in the RPC's Path B
    // even if the database-side `normalise_phone()` is the broken pre-022
    // version that doesn't recognise the `972…` (no plus) form.
    // The `if (x != null) x` pattern inside a `<String>[…]` literal type-
    // promotes `x` from `String?` to `String`, so no explicit `!` is needed.
    final seen = <String>{};
    final out = <String>[];
    final ordered = <String>[
      if (international != null) international,
      if (local != null) local,
      cleaned,
    ];
    for (final v in ordered) {
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }
    return out;
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
        debugPrint('Shadow user not found, creating new one...');
        try {
          await _supabase.auth.signUp(
            email: shadowEmail,
            password: password,
          );
          debugPrint('Shadow user created: $shadowEmail — retrying sign-in...');
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
  //
  // Phone matching is intentionally tolerant of formatting differences
  // between Supabase Auth (which always stores E.164, e.g. `+97252…`) and
  // the `authorized_apartments.residents` JSONB array (which may have been
  // populated by an admin using local format `052…` or country-code-without-
  // plus `97252…`). See [phoneVariations] for the full set of formats checked.
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

      // No profile found by id — try to link via phone using all known
      // format variations (raw, local 052…, international +97252…).
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

  /// Resolves the best display name for [profile].
  ///
  /// Order: existing [Profile.displayName] → Google metadata → name from
  /// `authorized_apartments.residents` matched by phone (persisted to profile).
  Future<String?> resolveDisplayName(Profile profile) async {
    final existing = profile.displayName?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    if (isGoogleUser) {
      await syncGoogleDisplayName();
      try {
        final response = await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', profile.id)
            .maybeSingle();
        final synced = (response?['display_name'] as String?)?.trim();
        if (synced != null && synced.isNotEmpty) return synced;
      } catch (e) {
        debugPrint('resolveDisplayName: google sync re-read failed: $e');
      }
    }

    final user = currentUser;
    if (user == null) return null;
    final phone = profile.phone ?? _resolveUserPhone(user);
    if (phone == null || phone.isEmpty) return null;

    final fromResidents = await _lookupNameFromAuthorizedResidents(phone);
    if (fromResidents == null || fromResidents.isEmpty) return null;

    try {
      await updateProfile(displayName: fromResidents);
    } catch (e) {
      debugPrint('resolveDisplayName: failed to persist name: $e');
    }
    return fromResidents;
  }

  /// Looks up a resident name in `authorized_apartments.residents` by phone.
  Future<String?> _lookupNameFromAuthorizedResidents(String phone) async {
    final targetVariations = phoneVariations(phone).toSet();
    if (targetVariations.isEmpty) return null;

    try {
      final rows = await _supabase.from('authorized_apartments').select('residents');

      for (final row in rows as List<dynamic>) {
        final residents = row['residents'];
        if (residents is! List) continue;
        for (final raw in residents) {
          if (raw is! Map) continue;
          final rPhone = (raw['phone'] as String?) ?? '';
          final matches = phoneVariations(rPhone)
              .any(targetVariations.contains);
          if (!matches) continue;
          final name = (raw['name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) return name;
        }
      }
    } catch (e) {
      debugPrint('_lookupNameFromAuthorizedResidents: $e');
    }
    return null;
  }

  /// Returns the best phone number we can derive for [user]:
  ///
  ///   - For OTP-authenticated users, [user.phone] is populated by Supabase
  ///     Auth in E.164 (e.g. `+97252…`) and is used directly.
  ///   - For the dev-bypass / `devImpersonate` flow the user signs in with
  ///     a synthetic email `dev_<digits>@parkingtrade.com` and Supabase Auth
  ///     leaves `phone` blank. We recover the phone digits from the email
  ///     local-part so the same robust matching path can run for bypass
  ///     users — otherwise dev bypass would always 404 against
  ///     `authorized_apartments`.
  ///
  /// Returns null when no phone-like value can be recovered.
  String? _resolveUserPhone(User user) {
    final fromAuth = user.phone;
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    final email = user.email;
    if (email == null || email.isEmpty) return null;

    // dev_<digits>@…  /  dev-<digits>@…  — extract the digits portion.
    final match = RegExp(r'^dev[_-]([0-9]+)@').firstMatch(email);
    if (match == null) return null;

    final digits = match.group(1);
    if (digits == null || digits.isEmpty) return null;
    return digits; // phoneVariations() will normalise this further.
  }

  /// Attempts to link the current auth user to a pre-created profile (or
  /// auto-create one) by calling the `link_profile_by_phone` database
  /// function (SECURITY DEFINER — bypasses RLS).
  ///
  /// Silently ignores errors — the caller will simply route to the
  /// not-registered screen if linking fails.
  ///
  /// NOTE: We intentionally do NOT query `authorized_apartments` directly
  /// from the client before calling the RPC. A freshly authenticated user
  /// has no profile row yet, so the RLS policy on `authorized_apartments`
  /// (migration 021) will deny the read — producing a misleading "no match"
  /// result even when the resident IS in the table. The SECURITY DEFINER
  /// RPC is the only path that can do this lookup safely.
  ///
  /// We try each phone-format variation in turn (canonical `+972…` first)
  /// so the DB-side `normalise_phone` helper is exercised and the link
  /// succeeds regardless of how the admin stored the phone.
  Future<void> _tryLinkProfileByPhone(User user) async {
    final phone = _resolveUserPhone(user);
    if (phone == null || phone.isEmpty) return;

    final variations = phoneVariations(phone);
    if (variations.isEmpty) return;

    debugPrint(
      '_tryLinkProfileByPhone: trying variations $variations for user ${user.id}',
    );

    for (final variant in variations) {
      try {
        await _supabase.rpc('link_profile_by_phone', params: {
          'p_user_id': user.id,
          'p_phone': variant,
        });

        // Did the RPC succeed in creating/linking a profile? If so, stop.
        final linked = await _supabase
            .from('profiles')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();
        if (linked != null) {
          debugPrint(
            '_tryLinkProfileByPhone: linked profile for user ${user.id} '
            'via variant "$variant"',
          );
          return;
        }
      } catch (e) {
        debugPrint('_tryLinkProfileByPhone($variant): $e');
        // Try the next variation.
      }
    }

    debugPrint(
      '_tryLinkProfileByPhone: exhausted all variations $variations for '
      'user ${user.id} without creating a profile — caller will route to '
      'the not-registered screen',
    );
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

