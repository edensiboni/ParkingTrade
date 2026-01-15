class SupabaseConfig {
  // These should be set via environment variables or build configuration
  // For production, use flutter_dotenv or --dart-define flags
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '', // Set your Supabase URL here
  );
  
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '', // Set your Supabase anon key here
  );
  
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

