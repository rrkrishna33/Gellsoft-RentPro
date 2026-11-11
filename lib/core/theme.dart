import 'package:flutter/material.dart';

/// Every colour in the app comes from here, so the look can be retuned in
/// one place.
///
/// RentPro is "Midnight and Gold": deep navy with gold. The dark theme is the
/// full midnight look; the light theme keeps the same gold and navy on warm
/// ivory.
class Palette {
  // Light: navy and gold on ivory
  static const primary = Color(0xFF1C2C54); // midnight navy
  static const onPrimary = Colors.white;
  static const primaryContainer = Color(0xFFF6E9C3); // soft gold
  static const onPrimaryContainer = Color(0xFF3B2C05);
  static const background = Color(0xFFFBF7EC); // warm ivory
  static const surface = Colors.white;
  static const ink = Color(0xFF14213D); // main text
  static const inkSoft = Color(0xFF5E6579); // secondary text
  static const outline = Color(0xFFD9CDA8); // input borders
  static const hairline = Color(0xFFEBE2C8); // card borders, dividers
  static const success = Color(0xFF2E7D4F);
  static const danger = Color(0xFFB3261E);
  static const warning = Color(0xFFB7791F);
  static const accent = Color(0xFFD5A64A); // gold, for highlights

  // Dark: midnight and gold
  static const darkPrimary = Color(0xFFE8C26A); // gold
  static const darkOnPrimary = Color(0xFF1A1405);
  static const darkBackground = Color(0xFF0C1426);
  static const darkSurface = Color(0xFF131D36);
  static const darkHairline = Color(0xFF27334F);
  static const darkInk = Color(0xFFEEF2F9);
  static const darkInkSoft = Color(0xFF93A0B8);
}

/// Colours for the colourful shortcut tiles on Home: gold first, then colours
/// that sit well on navy and on ivory.
const tileColors = <Color>[
  Color(0xFFD5A64A), // gold
  Color(0xFF4F7BD9), // blue
  Color(0xFF3FB68B), // green
  Color(0xFFD9577A), // rose
  Color(0xFF8A6BD9), // violet
  Color(0xFFE08A3C), // amber
  Color(0xFFB9743B), // copper
  Color(0xFF5C6F8F), // slate
];

/// The richer "Aurora" look: gradient hero cards and buttons, soft shadows and
/// a gently tinted page. Screens that use it read it from the theme, so light
/// and dark each get their own values.
@immutable
class AuroraStyle extends ThemeExtension<AuroraStyle> {
  const AuroraStyle({
    required this.page,
    required this.hero,
    required this.cta,
    required this.onCta,
    required this.softShadow,
    required this.heroShadow,
    required this.ctaShadow,
    required this.sheet,
  });

  /// Top-to-bottom colours of the page behind Home and Quick Bill.
  final List<Color> page;

  /// The big summary card on Home.
  final Gradient hero;

  /// The main buttons (Quick Bill, Cash).
  final Gradient cta;

  /// Text and icons on [cta].
  final Color onCta;

  final List<BoxShadow> softShadow;
  final List<BoxShadow> heroShadow;
  final List<BoxShadow> ctaShadow;

  /// The rounded bill panel in Quick Bill.
  final Color sheet;

  static const _navy = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C2C54), Color(0xFF16264A), Color(0xFF22345F)],
  );
  static const _gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF1D58A), Color(0xFFD5A64A)],
  );

  static const light = AuroraStyle(
    page: [Color(0xFFF6EBC8), Color(0xFFFDFBF4)],
    hero: _navy,
    cta: _gold,
    onCta: Color(0xFF1A1405),
    softShadow: [
      BoxShadow(color: Color(0x1F8A6B1B), blurRadius: 18, offset: Offset(0, 6)),
    ],
    heroShadow: [
      BoxShadow(
        color: Color(0x4D16264A),
        blurRadius: 30,
        offset: Offset(0, 14),
      ),
    ],
    ctaShadow: [
      BoxShadow(
        color: Color(0x4DD5A64A),
        blurRadius: 20,
        offset: Offset(0, 10),
      ),
    ],
    sheet: Colors.white,
  );

  static const dark = AuroraStyle(
    page: [Color(0xFF16213F), Color(0xFF0A1122)],
    hero: _navy,
    cta: _gold,
    onCta: Color(0xFF1A1405),
    softShadow: [
      BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 6)),
    ],
    heroShadow: [
      BoxShadow(
        color: Color(0x73000000),
        blurRadius: 30,
        offset: Offset(0, 14),
      ),
    ],
    ctaShadow: [
      BoxShadow(color: Color(0x4DD5A64A), blurRadius: 20, offset: Offset(0, 8)),
    ],
    sheet: Color(0xFF131D36),
  );

  /// The theme's style, or the one for its brightness when a test or an
  /// embedded theme left it out.
  static AuroraStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AuroraStyle>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AuroraStyle copyWith() => this;

  @override
  AuroraStyle lerp(ThemeExtension<AuroraStyle>? other, double t) => this;
}

/// The tinted page behind a screen. Put it around the Scaffold and give the
/// Scaffold a transparent background, so the app bar blends in too.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = AuroraStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: style.page,
        ),
      ),
      child: child,
    );
  }
}

class AppTheme {
  static const _radius = 16.0;

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Palette.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: Palette.primary,
          onPrimary: Palette.onPrimary,
          primaryContainer: Palette.primaryContainer,
          onPrimaryContainer: Palette.onPrimaryContainer,
          secondary: Palette.accent,
          tertiary: Palette.success,
          surface: Palette.surface,
          onSurface: Palette.ink,
          onSurfaceVariant: Palette.inkSoft,
          outline: Palette.outline,
          outlineVariant: Palette.hairline,
          error: Palette.danger,
          surfaceContainerLowest: Palette.surface,
          surfaceContainerLow: const Color(0xFFFAF6E8),
          surfaceContainer: const Color(0xFFF4EEDA),
          surfaceContainerHigh: const Color(0xFFEEE7CF),
          surfaceContainerHighest: const Color(0xFFE8E0C4),
        );
    return _build(scheme, Palette.background);
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Palette.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: Palette.darkPrimary,
          onPrimary: Palette.darkOnPrimary,
          primaryContainer: const Color(0xFF3B3117),
          onPrimaryContainer: const Color(0xFFF6E4B0),
          secondary: Palette.accent,
          surface: Palette.darkSurface,
          onSurface: Palette.darkInk,
          onSurfaceVariant: Palette.darkInkSoft,
          outline: const Color(0xFF34425F),
          outlineVariant: Palette.darkHairline,
          surfaceContainerLowest: Palette.darkBackground,
          surfaceContainerLow: const Color(0xFF101A30),
          surfaceContainer: const Color(0xFF16213B),
          surfaceContainerHigh: const Color(0xFF1C2847),
          surfaceContainerHighest: const Color(0xFF243253),
        );
    return _build(scheme, Palette.darkBackground);
  }

  static ThemeData _build(ColorScheme s, Color background) {
    const accents = TileAccents(colors: tileColors, tinted: true);
    final aurora = s.brightness == Brightness.dark
        ? AuroraStyle.dark
        : AuroraStyle.light;
    final dark = s.brightness == Brightness.dark;
    final base = ThemeData(brightness: s.brightness, useMaterial3: true);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radius),
    );
    final inputShape = BorderRadius.circular(14);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: inputShape,
      borderSide: BorderSide(color: c, width: w),
    );

    final text = base.textTheme
        .apply(bodyColor: s.onSurface, displayColor: s.onSurface)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            color: s.onSurfaceVariant,
          ),
        );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const buttonSize = Size(64, 48);

    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      extensions: [accents, aurora],
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: text,
      dividerTheme: DividerThemeData(
        color: s.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      // No bar and no line: the title sits on the page itself.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: s.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          color: s.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: s.surface,
        surfaceTintColor: Colors.transparent,
        elevation: dark ? 0 : 2,
        shadowColor: dark ? Colors.transparent : const Color(0x338A6B1B),
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: s.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: border(s.outline),
        enabledBorder: border(s.outline),
        focusedBorder: border(s.primary, 2),
        errorBorder: border(s.error),
        focusedErrorBorder: border(s.error, 2),
        labelStyle: TextStyle(color: s.onSurfaceVariant),
        helperStyle: TextStyle(color: s.onSurfaceVariant),
        prefixIconColor: s.onSurfaceVariant,
        suffixIconColor: s.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: s.outline),
          foregroundColor: s.primary,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        elevation: 2,
        highlightElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: s.surface,
        selectedColor: s.primaryContainer,
        side: BorderSide(color: s.outlineVariant),
        shape: const StadiumBorder(),
        showCheckmark: false,
        labelStyle: text.labelLarge?.copyWith(color: s.onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: buttonShape,
          side: BorderSide(color: s.outline),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? Colors.transparent
              : s.outline,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),
      popupMenuTheme: PopupMenuThemeData(
        color: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
    );
  }
}

/// Accent colours for the colourful tiles: product tiles in Quick Bill and
/// the shortcuts on Home. A theme that does not include this extension keeps
/// the plain look.
@immutable
class TileAccents extends ThemeExtension<TileAccents> {
  const TileAccents({required this.colors, this.tinted = false});

  final List<Color> colors;

  /// true: tiles get a soft tinted background; false: white tiles with
  /// coloured badges and prices.
  final bool tinted;

  /// The same product always gets the same colour (a stable hash of its name,
  /// not Dart's String.hashCode, which may differ between runs).
  Color forName(String name) {
    var h = 0;
    for (final c in name.runes) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return colors[h % colors.length];
  }

  Color at(int index) => colors[index % colors.length];

  @override
  TileAccents copyWith({List<Color>? colors, bool? tinted}) =>
      TileAccents(colors: colors ?? this.colors, tinted: tinted ?? this.tinted);

  @override
  TileAccents lerp(ThemeExtension<TileAccents>? other, double t) => this;
}
