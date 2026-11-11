import 'package:flutter/material.dart';

/// Every colour in the app comes from here, so the look can be retuned in
/// one place.
class Palette {
  // Light
  static const primary = Color(0xFF6B2D8C); // deep teal
  static const onPrimary = Colors.white;
  static const primaryContainer = Color(0xFFEBDDF5);
  static const onPrimaryContainer = Color(0xFF2E0F43);
  static const background = Color(0xFFF8F4FB); // cool page with a hint of teal
  static const surface = Colors.white;
  static const ink = Color(0xFF111827); // main text
  static const inkSoft = Color(0xFF5B6472); // secondary text
  static const outline = Color(0xFFD3C6DD); // input borders
  static const hairline = Color(0xFFE6DCEE); // card borders, dividers
  static const success = Color(0xFF2E7D4F);
  static const danger = Color(0xFFB3261E);
  static const warning = Color(0xFFB7791F);
  static const accent = Color(0xFFC98A1B); // warm gold, for highlights

  // Dark
  static const darkPrimary = Color(0xFFD9B8F0);
  static const darkOnPrimary = Color(0xFF2E0F43);
  static const darkBackground = Color(0xFF140F1A);
  static const darkSurface = Color(0xFF1D1625);
  static const darkHairline = Color(0xFF33283F);
  static const darkInk = Color(0xFFEDE6F3);
  static const darkInkSoft = Color(0xFFA99DB5);
}

/// Colours for the colourful tiles and shortcuts (Home and Quick Bill). Each
/// product / shortcut keeps its own colour, so staff learn items by colour.
const tileColors = <Color>[
  Color(0xFF6B2D8C), // teal
  Color(0xFFF2682F), // orange
  Color(0xFF2F6BDD), // blue
  Color(0xFFE0457B), // pink
  Color(0xFF7C4DDB), // violet
  Color(0xFF17A673), // mint
  Color(0xFFB7791F), // amber
  Color(0xFF3A4A5A), // slate
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

  static const light = AuroraStyle(
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
      BoxShadow(color: Color(0x176B2D8C), blurRadius: 18, offset: Offset(0, 6)),
    ],
    heroShadow: [
      BoxShadow(
        color: Color(0x526B2D8C),
        blurRadius: 30,
        offset: Offset(0, 14),
      ),
    ],
    ctaShadow: [
      BoxShadow(
        color: Color(0x4D6B2D8C),
        blurRadius: 20,
        offset: Offset(0, 10),
      ),
    ],
    sheet: Colors.white,
  );

  static const dark = AuroraStyle(
    page: [Color(0xFF1E1228), Color(0xFF120D18)],
    hero: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2B0E3E), Color(0xFF4F2069), Color(0xFF7A3A9A)],
    ),
    cta: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC79BE6), Color(0xFFD9B8F0)],
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
    ctaShadow: [
      BoxShadow(color: Color(0x4DC79BE6), blurRadius: 20, offset: Offset(0, 8)),
    ],
    sheet: Color(0xFF1D1625),
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
          secondary: const Color(0xFF475569),
          tertiary: Palette.success,
          surface: Palette.surface,
          onSurface: Palette.ink,
          onSurfaceVariant: Palette.inkSoft,
          outline: Palette.outline,
          outlineVariant: Palette.hairline,
          error: Palette.danger,
          surfaceContainerLowest: Palette.surface,
          surfaceContainerLow: const Color(0xFFF8F9FB),
          surfaceContainer: const Color(0xFFF1F3F7),
          surfaceContainerHigh: const Color(0xFFEBEEF3),
          surfaceContainerHighest: const Color(0xFFE5E9EF),
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
          primaryContainer: const Color(0xFF4A2461),
          onPrimaryContainer: const Color(0xFFF1DDFB),
          surface: Palette.darkSurface,
          onSurface: Palette.darkInk,
          onSurfaceVariant: Palette.darkInkSoft,
          outline: const Color(0xFF4A3B59),
          outlineVariant: Palette.darkHairline,
          surfaceContainerLowest: Palette.darkBackground,
          surfaceContainerLow: const Color(0xFF19121F),
          surfaceContainer: const Color(0xFF221929),
          surfaceContainerHigh: const Color(0xFF2A2033),
          surfaceContainerHighest: const Color(0xFF33283F),
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
        shadowColor: dark ? Colors.transparent : const Color(0x336B2D8C),
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
