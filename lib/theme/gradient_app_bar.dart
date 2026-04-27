import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A thin (3px) gradient hairline that can be placed at the bottom of an
/// AppBar (via `bottom`) to add a subtle premium accent — like the colored
/// stripes used by Stripe and Linear.
///
/// Usage:
/// ```dart
/// AppBar(
///   title: ...,
///   bottom: const BrandAccentBar(),
/// )
/// ```
class BrandAccentBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAccentBar({super.key, this.height = 3});

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.brandIndigo,
            AppTheme.brandViolet,
            AppTheme.brandTeal,
          ],
        ),
      ),
    );
  }
}

/// A flexible-space gradient header that can replace AppBar backgrounds for
/// hero sections or onboarding flows without giving up the AppBar API.
class BrandGradientFlexibleSpace extends StatelessWidget {
  const BrandGradientFlexibleSpace({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.brandGradient,
      ),
    );
  }
}
