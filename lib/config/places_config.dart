/// Google Places API key for address autocomplete.
/// Set via --dart-define=PLACES_API_KEY=... or from environment in run_web.sh.
/// If empty, create-building will fall back to plain text (no autocomplete).
class PlacesConfig {
  static const String placesApiKey = String.fromEnvironment(
    'PLACES_API_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => placesApiKey.isNotEmpty;
}
