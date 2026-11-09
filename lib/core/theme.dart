import 'package:flutter/material.dart';

/// Every colour in the app comes from here, so the look can be retuned in
/// one place. RentPro is "Royal Plum": deep plum with warm gold, so it never
/// looks like its sister app BillPro (teal).
class Palette {
  // Light
  static const primary = Color(0xFF6B2D8C); // royal plum
  static const onPrimary = Colors.white;
  static const primaryContainer = Color(0xFFEBDDF5);
  static const onPrimaryContainer = Color(0xFF2E0F43);
  static const accent = Color(0xFFC98A1B); // warm gold
  static const background = Color(0xFFF8F4FB);
  static const surface = Colors.white;
  static const ink = Color(0xFF1B1423);
  static const inkSoft = Color(0xFF6A6073);
  static const outline = Color(0xFFD3C6DD);
  static const hairline = Color(0xFFE6DCEE);
  static const success = Color(0xFF2E7D4F);
  static const warning = Color(0xFFB7791F);
  static const danger = Color(0xFFB3261E);

  // Dark
  static const darkPrimary = Color(0xFFD9B8F0);
  static const darkOnPrimary = Color(0xFF2E0F43);
  static const darkBackground = Color(0xFF140F1A);
  static const darkSurface = Color(0xFF1D1625);
  static const darkHairline = Color(0xFF33283F);
  static const darkInk = Color(0xFFEDE6F3);
  static const darkInkSoft = Color(0xFFA99DB5);
}

/// The richer look: a gradient hero card and buttons, soft shadows and a
/// gently tinted page. Screens read it from the theme, so light and dark each
/// get their own values.
@immutable
class RentStyle extends ThemeExtension<RentStyle> {
  const RentStyle({
    required this.page,
    required this.hero,
    required this.cta,
    required this.onCta,
    required this.softShadow,
    required this.heroShadow,
  });

  /// Top-to-bottom colours of the page behind Home.
  final List<Color> page;

  /// The big summary card on Home.
  final Gradient hero;

  /// The main buttons.
  final Gradient cta;

  /// Text and icons on [cta].
  final Color onCta;

  final List<BoxShadow> softShadow;
  final List<BoxShadow> heroShadow;

  static const light = RentStyle(
    page: [Color(0xFFF0E6F7), Color(0xFFFAF7FC)],
    hero: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3F1259), Color(0xFF6B2D8C), Color(0xFFA24FC2)],
    ),
    cta: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF5A2278), Color(0xFF8E3FB5)],
    ),
    onCta: Colors.white,
    softShadow: [
      BoxShadow(color: Color(0x1A6B2D8C), blurRadius: 18, offset: Offset(0, 6)),
    ],
    heroShadow: [
      BoxShadow(
        color: Color(0x526B2D8C),
        blurRadius: 30,
        offset: Offset(0, 14),
      ),
    ],
  );

  static const dark = RentStyle(
    page: [Color(0xFF1E1228), Color(0xFF120D18)],
    hero: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2B0E3E), Color(0xFF4F2069), Color(0xFF7A3A9A)],
    ),
    cta: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC79BE6), Color(0xFFE2C6F5)],
    ),
    onCta: Color(0xFF2E0F43),
    softShadow: [
      BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 6)),
    ],
    heroShadow: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 30,
        offset: Offset(0, 14),
      ),
    ],
  );

  /// The theme's style, or the one for its brightness when a test or an
  /// embedded theme left it out.
  static RentStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<RentStyle>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  RentStyle copyWith() => this;

  @override
  RentStyle lerp(ThemeExtension<RentStyle>? other, double t) =>
      t < 0.5 ? this : (other as RentStyle? ?? this);
}

/// The tinted page behind a screen.
class RentBackground extends StatelessWidget {
  const RentBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = RentStyle.of(context).page;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: page,
        ),
      ),
      child: child,
    );
  }
}

class AppTheme {
  static const _radius = 16.0;
  static const String? _font = null; // the phone's own fonts cover Tamil

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: Palette.primary,
      onPrimary: Palette.onPrimary,
      primaryContainer: Palette.primaryContainer,
      onPrimaryContainer: Palette.onPrimaryContainer,
      secondary: Palette.accent,
      surface: Palette.surface,
      onSurface: Palette.ink,
      onSurfaceVariant: Palette.inkSoft,
      outline: Palette.outline,
      outlineVariant: Palette.hairline,
      error: Palette.danger,
    ),
    Palette.background,
    RentStyle.light,
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: Palette.darkPrimary,
      onPrimary: Palette.darkOnPrimary,
      primaryContainer: const Color(0xFF4A2461),
      onPrimaryContainer: const Color(0xFFF1DDFB),
      secondary: const Color(0xFFE8B44C),
      surface: Palette.darkSurface,
      onSurface: Palette.darkInk,
      onSurfaceVariant: Palette.darkInkSoft,
      outline: const Color(0xFF4A3B59),
      outlineVariant: Palette.darkHairline,
    ),
    Palette.darkBackground,
    RentStyle.dark,
  );

  static ThemeData _build(ColorScheme s, Color background, RentStyle style) {
    final dark = s.brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radius),
    );
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      fontFamily: _font,
      scaffoldBackgroundColor: background,
      extensions: [style],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: s.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: s.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surface,
        border: border(s.outline),
        enabledBorder: border(s.outline),
        focusedBorder: border(s.primary, 2),
        errorBorder: border(s.error),
        focusedErrorBorder: border(s.error, 2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontFamily: _font,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: s.outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surface,
        indicatorColor: s.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: s.onSurface,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: s.outlineVariant, space: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: s.outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(shape: shape, backgroundColor: s.surface),
      brightness: dark ? Brightness.dark : Brightness.light,
    );
  }
}
