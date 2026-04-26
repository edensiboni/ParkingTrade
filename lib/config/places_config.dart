import 'package:flutter/foundation.dart' show debugPrint;

/// Google Places API key for address autocomplete.
///
/// **How to set it:**
/// - Local dev: pass `--dart-define=PLACES_API_KEY=<key>` to `flutter run` / `flutter build`.
/// - Web dev script: add `PLACES_API_KEY` to your `run_web.sh` / `Makefile` alongside the Supabase vars.
/// - CI/CD: add the `PLACES_API_KEY` secret to your GitHub Actions workflow.
///
/// If the key is empty the [AddressAutocompleteField] falls back to a plain text
/// field — address entry still works, just without autocomplete suggestions.
class PlacesConfig {
  static const String placesApiKey = String.fromEnvironment(
    'PLACES_API_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => placesApiKey.isNotEmpty;

  /// Call once at app start to emit a visible warning when the key is absent.
  static void warnIfMissing() {
    if (!isConfigured) {
      debugPrint(
        '⚠️  [PlacesConfig] PLACES_API_KEY is not set. '
        'Address autocomplete will fall back to plain text input. '
        'Pass --dart-define=PLACES_API_KEY=<your_key> when building/running.',
      );
    }
  }
}
