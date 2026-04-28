import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-wide theme: a premium, modern Material 3 system inspired by
/// Stripe, Linear, and Vercel.
///
/// Design pillars:
/// - **Quiet luxury palette** — soft off-white background, deep indigo primary,
///   gentle surface tints. No harsh whites, no aggressive shadows.
/// - **Generous geometry** — 16–20px radii on cards, pill buttons, big inputs
///   with soft fills (no harsh underlines).
/// - **Modern typography** — Heebo: a clean, highly readable Google Font with
///   first-class Hebrew + Latin support, perfect for an RTL/Hebrew product.
/// - **Layered surfaces** — instead of elevation/shadows, surfaces are
///   distinguished by subtle color shifts, hairline borders, and tints.
/// - **Joyful micro-interactions** — gradient AppBar accents, soft hover/press
///   tints on interactive surfaces, animated splashes.
class AppTheme {
  AppTheme._();

  // ── Brand palette ──────────────────────────────────────────────────────────
  // A calm royal-indigo: confident, professional, and works beautifully with
  // both Hebrew and Latin script. Pairs with a warm secondary for accents.
  static const Color brandIndigo = Color(0xFF4F46E5); // primary (indigo-600)
  static const Color brandIndigoDeep = Color(0xFF3730A3); // gradient end
  static const Color brandViolet = Color(0xFF7C3AED); // secondary accent
  static const Color brandTeal = Color(0xFF0EA5A4); // tertiary highlight

  // Semantic colors — calibrated for accessibility on light backgrounds.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // Soft surface tones — replace stark white with a warm, luxurious off-white.
  static const Color appBackground = Color(0xFFF7F8FB); // canvas
  static const Color cardSurface = Color(0xFFFFFFFF); // raised card
  static const Color subtleSurface = Color(0xFFF1F3F9); // input fill / chips
  static const Color hairline = Color(0xFFE6E8EF); // 1px borders

  // Text tones — use `ink` instead of pure black for a premium feel.
  static const Color ink = Color(0xFF0F172A); // slate-900
  static const Color inkMuted = Color(0xFF475569); // slate-600
  static const Color inkSoft = Color(0xFF94A3B8); // slate-400

  // Common radii — chunky and modern.
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  // Common spacing.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;

  // Brand gradient — reusable for AppBars, hero sections, badges.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandIndigo, brandViolet],
  );

  static const LinearGradient subtleSurfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFCFCFE), Color(0xFFF4F6FB)],
  );

  static ThemeData light() {
    final scheme = const ColorScheme(
      brightness: Brightness.light,
      primary: brandIndigo,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE0E7FF), // indigo-100
      onPrimaryContainer: brandIndigoDeep,
      secondary: brandViolet,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFEDE9FE), // violet-100
      onSecondaryContainer: const Color(0xFF5B21B6),
      tertiary: brandTeal,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFCCFBF1),
      onTertiaryContainer: const Color(0xFF0F766E),
      error: danger,
      onError: Colors.white,
      errorContainer: const Color(0xFFFEE2E2),
      onErrorContainer: const Color(0xFF7F1D1D),
      surface: appBackground,
      onSurface: ink,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFCFCFE),
      surfaceContainer: cardSurface,
      surfaceContainerHigh: subtleSurface,
      surfaceContainerHighest: const Color(0xFFE9ECF4),
      onSurfaceVariant: inkMuted,
      outline: hairline,
      outlineVariant: const Color(0xFFEEF1F6),
      shadow: const Color(0x14000000),
      scrim: const Color(0x33000000),
      inverseSurface: ink,
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFFA5B4FC),
      surfaceTint: brandIndigo,
    );

    // ── Typography: Heebo (excellent RTL/Hebrew + Latin readability) ─────────
    // GoogleFonts.heeboTextTheme() returns a Material text theme using Heebo
    // for every text style. We then refine weights/letter-spacing for a
    // modern, magazine-grade feel.
    final base = GoogleFonts.heeboTextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    final textTheme = base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.05,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.08,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.15,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: inkMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: appBackground,
      canvasColor: appBackground,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      // Subtle hover/focus tinting across all interactive surfaces.
      hoverColor: brandIndigo.withValues(alpha: 0.04),
      focusColor: brandIndigo.withValues(alpha: 0.10),
      highlightColor: brandIndigo.withValues(alpha: 0.06),
      splashColor: brandIndigo.withValues(alpha: 0.10),

      // ── App Bar: clean, flat, premium ──────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: appBackground,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 24,
        toolbarHeight: 68,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: ink, size: 22),
        actionsIconTheme: const IconThemeData(color: inkMuted, size: 22),
        shape: const Border(
          bottom: BorderSide(color: hairline, width: 1),
        ),
      ),

      // ── Cards: white surface, subtle hairline border, soft radius ──────────
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cardSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x0F0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: hairline, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      dividerTheme: const DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        iconColor: inkMuted,
        textColor: ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: inkMuted),
        minVerticalPadding: 12,
      ),

      // ── Inputs: soft fill, rounded, no harsh borders ───────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: subtleSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: Color(0xFFE6E8EF), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: brandIndigo, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: danger, width: 1.6),
        ),
        prefixIconColor: inkMuted,
        suffixIconColor: inkMuted,
        hintStyle: textTheme.bodyMedium?.copyWith(color: inkSoft),
        labelStyle: textTheme.bodyMedium?.copyWith(color: inkMuted),
        floatingLabelStyle: textTheme.labelLarge?.copyWith(
          color: brandIndigo,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: danger),
      ),

      // ── Buttons: chunky, rounded, hover-aware ──────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return brandIndigo.withValues(alpha: 0.4);
            }
            if (states.contains(WidgetState.hovered)) {
              return brandIndigoDeep;
            }
            return brandIndigo;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.10);
            }
            return Colors.transparent;
          }),
          mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return brandIndigo.withValues(alpha: 0.4);
            }
            if (states.contains(WidgetState.hovered)) {
              return brandIndigoDeep;
            }
            return brandIndigo;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return const BorderSide(color: brandIndigo, width: 1.4);
            }
            return const BorderSide(color: Color(0xFFD8DCE6), width: 1.2);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return brandIndigo.withValues(alpha: 0.04);
            }
            return Colors.transparent;
          }),
          foregroundColor: const WidgetStatePropertyAll(ink),
          mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return brandIndigoDeep;
            return brandIndigo;
          }),
          overlayColor: const WidgetStatePropertyAll(
            Color(0x0F4F46E5),
          ),
          mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return ink;
            return inkMuted;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return brandIndigo.withValues(alpha: 0.06);
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        focusElevation: 6,
        hoverElevation: 8,
        highlightElevation: 6,
        backgroundColor: brandIndigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),

      // ── Chips: pill-shaped, soft fill ──────────────────────────────────────
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: subtleSurface,
        side: const BorderSide(color: hairline),
        shape: const StadiumBorder(),
        showCheckmark: false,
        selectedColor: const Color(0xFFE0E7FF),
        secondarySelectedColor: const Color(0xFFE0E7FF),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: brandIndigoDeep,
          fontWeight: FontWeight.w700,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        actionTextColor: const Color(0xFFA5B4FC),
        elevation: 6,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: hairline),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        showDragHandle: true,
        dragHandleColor: inkSoft,
      ),

      // ── Tabs: clean underline, primary accent ──────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: brandIndigo,
        unselectedLabelColor: inkMuted,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        dividerColor: hairline,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: brandIndigo, width: 2.4),
          insets: EdgeInsets.symmetric(horizontal: 4),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return brandIndigo.withValues(alpha: 0.06);
          }
          return Colors.transparent;
        }),
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brandIndigo,
        linearTrackColor: subtleSurface,
        circularTrackColor: subtleSurface,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brandIndigo;
          return const Color(0xFFCBD2DD);
        }),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        side: const BorderSide(color: Color(0xFFCBD2DD), width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brandIndigo;
          return Colors.white;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brandIndigo;
          return inkSoft;
        }),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}
