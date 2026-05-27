import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/salon_branding.dart';
import '../models/salon_theme_config.dart';
import '../services/salon_theme_service.dart';
import '../theme/app_theme.dart';

/// Deep-link salon identifier query parameter.
const salonIdQueryParam = 'id';

/// Custom URL scheme used in QR codes: `stylecast://salon?id=<uuid>`.
const stylecastDeepLinkScheme = 'stylecast';
const stylecastSalonHost = 'salon';

String buildSalonDeepLink(String salonId) =>
    '$stylecastDeepLinkScheme://$stylecastSalonHost?$salonIdQueryParam=$salonId';

class SalonThemeState {
  final ThemeData themeData;
  final SalonThemeConfig? config;
  final bool isLoading;

  const SalonThemeState({
    required this.themeData,
    this.config,
    this.isLoading = false,
  });

  factory SalonThemeState.neutral() => SalonThemeState(
        themeData: AppTheme.light(),
      );

  SalonThemeState copyWith({
    ThemeData? themeData,
    SalonThemeConfig? config,
    bool clearConfig = false,
    bool? isLoading,
  }) {
    return SalonThemeState(
      themeData: themeData ?? this.themeData,
      config: clearConfig ? null : (config ?? this.config),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SalonThemeNotifier extends Notifier<SalonThemeState> {
  final _service = SalonThemeService();

  @override
  SalonThemeState build() => SalonThemeState.neutral();

  /// Validates [salonId], fetches branding, or resets to the neutral theme.
  Future<void> loadTheme(String salonId) async {
    final trimmed = salonId.trim();
    if (!_isValidUuid(trimmed)) {
      resetToNeutral();
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final config = await _service.fetchSalonTheme(trimmed);
      if (config == null) {
        resetToNeutral();
        return;
      }
      state = SalonThemeState(
        themeData: _themeFromConfig(config),
        config: config,
        isLoading: false,
      );
    } catch (_) {
      resetToNeutral();
    }
  }

  void resetToNeutral() {
    state = SalonThemeState.neutral();
  }

  bool _isValidUuid(String value) {
    try {
      Uuid.parse(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  ThemeData _themeFromConfig(SalonThemeConfig config) {
    final base = AppTheme.light();
    final primary =
        config.primaryColor ?? SalonBranding.primaryColorFromSalonId(config.salonId);

    final secondary = config.secondaryColor ?? AppTheme.brandViolet;
    final scheme = base.colorScheme.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      primaryContainer: Color.alphaBlend(
        primary.withValues(alpha: 0.12),
        AppTheme.cardSurface,
      ),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: _onColor(secondary),
      surfaceTint: primary,
    );

    return base.copyWith(
      colorScheme: scheme,
      appBarTheme: base.appBarTheme.copyWith(
        foregroundColor: AppTheme.ink,
      ),
    );
  }

  Color _onColor(Color background) {
    return background.computeLuminance() > 0.5 ? AppTheme.ink : Colors.white;
  }
}

final salonThemeProvider =
    NotifierProvider<SalonThemeNotifier, SalonThemeState>(
  SalonThemeNotifier.new,
);
