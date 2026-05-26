/// Custom URL scheme deep links for salon (building) branded entry.
class DeepLinkConfig {
  DeepLinkConfig._();

  static const String scheme = 'stylecast';
  static const String host = 'salon';

  static String linkForSalon(String salonId) => '$scheme://$host?id=$salonId';

  /// Returns the salon id when [uri] matches `stylecast://salon?id=…`.
  static String? salonIdFromUri(Uri uri) {
    final matchesHost = uri.host == host;
    final matchesPath = uri.path == '/$host' || uri.path == host;
    if (uri.scheme != scheme || (!matchesHost && !matchesPath)) {
      return null;
    }
    final id = uri.queryParameters['id']?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }
}
