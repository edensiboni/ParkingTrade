import 'package:flutter/material.dart';

class SalonBranding {
  final String salonId;
  final String displayName;
  final Color primaryColor;

  const SalonBranding({
    required this.salonId,
    required this.displayName,
    required this.primaryColor,
  });

  /// Deterministic accent color derived from the salon UUID.
  static Color primaryColorFromSalonId(String salonId) {
    final hex = salonId.replaceAll('-', '');
    final slice = hex.length >= 6 ? hex.substring(0, 6) : hex.padRight(6, '0');
    final value = int.tryParse(slice, radix: 16) ?? 0;
    final hue = value % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.52, 0.44).toColor();
  }
}
