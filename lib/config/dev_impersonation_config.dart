import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// DEV IMPERSONATION CONFIG
// ---------------------------------------------------------------------------
// All identifiers here are ONLY compiled into debug builds (kDebugMode).
// In release builds this entire class is inert — the const `enabled` flag
// is false, and the dart compiler tree-shakes the rest away.
//
// HOW TO ADD A TEST NUMBER:
//   1. Make sure the phone number exists in Supabase `auth.users` AND has a
//      matching row in `profiles` (i.e. is a registered resident).
//   2. Also create a Supabase Auth email+password user whose email follows the
//      pattern  dev+<digits>@parkingtrade.dev  (replace <digits> with the
//      national phone digits, no country code, no leading zero).
//      e.g. for +972523552350 → dev+523552350@parkingtrade.dev
//   3. Add an entry to [testNumbers] below.
//
// WHY email+password?
//   Supabase does not let you forge a phone-OTP session client-side. The
//   cleanest dev workaround is a mirror email/password account that shares
//   the same `profiles` row (same user_id) so the app sees the exact same
//   profile, building, and spot data.
// ---------------------------------------------------------------------------

class DevImpersonationConfig {
  /// Master toggle — true only in Flutter debug builds.
  static const bool enabled = kDebugMode;

  /// The magic OTP code accepted in dev mode (skips server round-trip).
  static const String masterOtp = '123456';

  /// Prefix used to derive the shadow email for each test number.
  /// e.g. +972523552350 → "dev+523552350@parkingtrade.dev"
  static const String emailDomain = 'parkingtrade.dev';
  static const String emailPrefix = 'dev+';

  /// Registered test phone numbers shown in the dev picker.
  /// Key   = human-readable label shown in the UI.
  /// Value = E.164 phone number that exists in `profiles`.
  static const Map<String, String> testNumbers = {
    'Marom (+972 52-355-2350)': '+972523552350',
    // Add more test residents here as needed:
    // 'Resident B (+972 50-000-0001)': '+972500000001',
  };

  /// Derives the shadow email for [e164Phone].
  /// Strips the country code prefix and leading zeros, prepends the email prefix.
  static String shadowEmail(String e164Phone) {
    // Strip leading '+' and country code heuristically:
    // For Israeli numbers (+972XXXXXXXXX) we strip "+972".
    // For other countries we fall back to stripping the '+' and first 3 chars.
    String digits = e164Phone.replaceFirst('+', '');
    // Remove common country codes (972 = Israel, 1 = US/CA, 44 = UK …)
    // We use a simple heuristic: keep only the subscriber part (last 9–10 digits).
    if (digits.startsWith('972') && digits.length == 12) {
      digits = digits.substring(3); // strip 972 → 523552350
    } else if (digits.startsWith('1') && digits.length == 11) {
      digits = digits.substring(1);
    } else {
      // Generic: strip first 2–3 chars (country code).
      digits = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    }
    return '$emailPrefix$digits@$emailDomain';
  }
}
