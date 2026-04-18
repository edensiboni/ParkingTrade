class DevAuthConfig {
  static const bool isEnabled = bool.fromEnvironment(
    'DEV_AUTH_ENABLED',
    defaultValue: false,
  );
}
