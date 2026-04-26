class SupabaseConfig {
  // Values are injected at build time via --dart-define=SUPABASE_URL=... etc.
  // Never hardcode real credentials here. Keep secrets in .env (gitignored) or
  // GitHub Actions secrets only.

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  // Publishable key (formerly called "anon key" - safe for client-side use).
  // run_web.sh passes this as SUPABASE_PUBLISHABLE_KEY; legacy SUPABASE_ANON_KEY
  // is also accepted for backward compatibility.
  static const String _publishableKeyFromEnv = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  static const String _anonKeyFromEnv = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // Use getter to check both env vars at runtime (can't use conditional logic in const).
  static String get supabasePublishableKey {
    if (_publishableKeyFromEnv.isNotEmpty) return _publishableKeyFromEnv;
    if (_anonKeyFromEnv.isNotEmpty) return _anonKeyFromEnv;
    return '';
  }

  // Legacy getter for backward compatibility.
  @Deprecated('Use supabasePublishableKey instead')
  static String get supabaseAnonKey => supabasePublishableKey;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// True when no credentials were injected at build time.
  /// Run the app via run_web.sh (or pass --dart-define flags manually) to fix this.
  static bool get isPlaceholder => supabaseUrl.isEmpty || supabasePublishableKey.isEmpty;
}

