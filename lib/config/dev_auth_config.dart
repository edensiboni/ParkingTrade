class DevAuthUser {
  final String label;
  final String email;
  final String password;

  const DevAuthUser({
    required this.label,
    required this.email,
    required this.password,
  });
}

/// Dev/test-only configuration for bypassing OTP using email/password.
///
/// Enabled when `--dart-define=DEV_AUTH_ENABLED=true`.
class DevAuthConfig {
  static const String _enabled =
      String.fromEnvironment('DEV_AUTH_ENABLED', defaultValue: 'false');

  static bool get isEnabled => _enabled == 'true';

  static String _env(String key) {
    return String.fromEnvironment(key, defaultValue: '');
  }

  static List<DevAuthUser> get users {
    const labels = ['A', 'B', 'C'];

    final out = <DevAuthUser>[];
    for (final label in labels) {
      final email = _env('DEV_AUTH_USER_${label}_EMAIL');
      final password = _env('DEV_AUTH_USER_${label}_PASSWORD');
      if (email.trim().isNotEmpty && password.trim().isNotEmpty) {
        out.add(
          DevAuthUser(
            label: label,
            email: email.trim(),
            password: password,
          ),
        );
      }
    }

    return out;
  }
}
