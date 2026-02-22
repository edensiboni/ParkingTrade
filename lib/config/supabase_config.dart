class SupabaseConfig {
  // Defaults match .env.example so app starts without --dart-define; replace via .env + run_web.sh or --dart-define.
  static const String _defaultUrl = 'https://YOUR_PROJECT.supabase.co';
  static const String _defaultPublishableKey = 'your-publishable-key';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultUrl,
  );

  // Publishable key (formerly called "anon key" - safe for client-side use)
  // Check SUPABASE_PUBLISHABLE_KEY first (new), then SUPABASE_ANON_KEY (legacy), then default
  static const String _publishableKeyFromEnv = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  static const String _anonKeyFromEnv = String.fromEnvironment(
    'SUPABASE_ANON_KEY', // Legacy name, still supported
    defaultValue: '',
  );
  
  // Use getter to check both env vars at runtime (can't use conditional logic in const)
  static String get supabasePublishableKey {
    if (_publishableKeyFromEnv.isNotEmpty) {
      return _publishableKeyFromEnv;
    }
    if (_anonKeyFromEnv.isNotEmpty) {
      return _anonKeyFromEnv;
    }
    return _defaultPublishableKey;
  }

  // Legacy getter for backward compatibility
  @Deprecated('Use supabasePublishableKey instead')
  static String get supabaseAnonKey => supabasePublishableKey;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// True if still using placeholder values (edit .env with real credentials).
  static bool get isPlaceholder =>
      supabaseUrl == _defaultUrl || supabasePublishableKey == _defaultPublishableKey;
}

