import 'package:flutter/material.dart';

/// Branding payload for a salon, loaded from Supabase (`salons` table).
class SalonThemeConfig {
  final String salonId;
  final String? name;
  final Color? primaryColor;
  final Color? secondaryColor;
  final String? logoUrl;

  const SalonThemeConfig({
    required this.salonId,
    this.name,
    this.primaryColor,
    this.secondaryColor,
    this.logoUrl,
  });

  factory SalonThemeConfig.fromJson(
    String salonId,
    Map<String, dynamic> json,
  ) {
    return SalonThemeConfig(
      salonId: salonId,
      name: json['name'] as String?,
      primaryColor: _parseColor(json['primary_color']),
      secondaryColor: _parseColor(json['secondary_color']),
      logoUrl: json['logo_url'] as String?,
    );
  }

  static Color? _parseColor(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    var hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }
}
