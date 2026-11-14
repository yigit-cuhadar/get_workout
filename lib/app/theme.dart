import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The app's looks, drawn in GetWorkout Studio. One ships when the app is
/// finished; until then Slate, and debug builds can switch in Profile.
enum AppPreset {
  slate(
    ForgePreset.slate,
    light: GwColors.light(
      bandBelow: Color(0xFF9AA3B2),
      bandIn: Color(0xFF222B38),
      bandOver: Color(0xFFA6473C),
    ),
    dark: GwColors.dark(
      bandBelow: Color(0xFF6B7689),
      bandIn: Color(0xFFEEF1F5),
      bandOver: Color(0xFFE0907F),
    ),
  ),
  measure(
    ForgePreset(
      name: 'Measure',
      sans: 'InstrumentSans',
      mono: 'IBMPlexMono',
      radii: ForgeRadii(sm: 8, md: 10, lg: 12),
      outlinedInDark: true,
      light: ForgePalette(
        ground: Color(0xFFF6F7F9),
        surface: Color(0xFFFFFFFF),
        surfaceBar: Color(0xFFFFFFFF),
        surfaceSunken: Color(0xFFEEF0F4),
        line: Color(0xFFDDE1E8),
        lineStrong: Color(0xFF8A93A3),
        ink: Color(0xFF12161F),
        inkMuted: Color(0xFF5B6474),
        inkSubtle: Color(0xFF5B6474),
        accent: Color(0xFF1F4FD8),
        onAccent: Color(0xFFFFFFFF),
        accentSoft: Color(0xFFE6ECFD),
        onAccentSoft: Color(0xFF12307F),
        featured: Color(0xFFE6ECFD),
        onFeatured: Color(0xFF0C1E55),
        featuredBorder: Color(0xFFB9C8F7),
        featuredAction: Color(0xFF1F4FD8),
        onFeaturedAction: Color(0xFFFFFFFF),
        success: Color(0xFF2E7D5B),
        info: Color(0xFF0F8A8A),
        danger: Color(0xFFC2341D),
      ),
      dark: ForgePalette(
        ground: Color(0xFF0E1117),
        surface: Color(0xFF161B24),
        surfaceBar: Color(0xFF161B24),
        surfaceSunken: Color(0xFF232A37),
        line: Color(0xFF2A3140),
        lineStrong: Color(0xFF6B7587),
        ink: Color(0xFFEEF1F6),
        inkMuted: Color(0xFF9AA4B5),
        inkSubtle: Color(0xFF9AA4B5),
        accent: Color(0xFF7FA0FF),
        onAccent: Color(0xFF0C1430),
        accentSoft: Color(0xFF1B2A55),
        onAccentSoft: Color(0xFFDCE5FF),
        featured: Color(0xFF1B2A55),
        onFeatured: Color(0xFFDCE5FF),
        featuredBorder: Color(0xFF2F4487),
        featuredAction: Color(0xFF7FA0FF),
        onFeaturedAction: Color(0xFF0C1430),
        success: Color(0xFF6FC29A),
        info: Color(0xFF4FD1C5),
        danger: Color(0xFFFF8A75),
      ),
    ),
    light: GwColors.light(
      bandBelow: Color(0xFF8FB0F5),
      bandIn: Color(0xFF1F4FD8),
      bandOver: Color(0xFFC2341D),
    ),
    dark: GwColors.dark(
      bandBelow: Color(0xFF3F5BB5),
      bandIn: Color(0xFF7FA0FF),
      bandOver: Color(0xFFFF8A75),
    ),
  ),
  graphite(
    ForgePreset(
      name: 'Graphite',
      sans: 'packages/forge_ui/Geist',
      mono: 'packages/forge_ui/GeistMono',
      radii: ForgeRadii(sm: 10, md: 12, lg: 14),
      outlinedInDark: true,
      light: ForgePalette(
        ground: Color(0xFFF3F3F2),
        surface: Color(0xFFFFFFFF),
        surfaceBar: Color(0xFFFFFFFF),
        surfaceSunken: Color(0xFFEBEBE9),
        line: Color(0xFFE2E2E0),
        lineStrong: Color(0xFF8E8E8A),
        ink: Color(0xFF161616),
        inkMuted: Color(0xFF5F5F5C),
        inkSubtle: Color(0xFF767672),
        accent: Color(0xFF161616),
        onAccent: Color(0xFFFFFFFF),
        accentSoft: Color(0xFFEBEBE9),
        onAccentSoft: Color(0xFF161616),
        featured: Color(0xFFFFFFFF),
        onFeatured: Color(0xFF161616),
        featuredBorder: Color(0xFF161616),
        featuredAction: Color(0xFF161616),
        onFeaturedAction: Color(0xFFFFFFFF),
        success: Color(0xFF3F7D62),
        info: Color(0xFF5B6F8C),
        danger: Color(0xFFA6473C),
      ),
      dark: ForgePalette(
        ground: Color(0xFF111111),
        surface: Color(0xFF1A1A1A),
        surfaceBar: Color(0xFF1A1A1A),
        surfaceSunken: Color(0xFF262625),
        line: Color(0xFF2A2A29),
        lineStrong: Color(0xFF6E6E6B),
        ink: Color(0xFFEDEDEC),
        inkMuted: Color(0xFFA3A3A0),
        inkSubtle: Color(0xFF8E8E8A),
        accent: Color(0xFFEDEDEC),
        onAccent: Color(0xFF111111),
        accentSoft: Color(0xFF2A2A29),
        onAccentSoft: Color(0xFFEDEDEC),
        featured: Color(0xFF1A1A1A),
        onFeatured: Color(0xFFEDEDEC),
        featuredBorder: Color(0xFFEDEDEC),
        featuredAction: Color(0xFFEDEDEC),
        onFeaturedAction: Color(0xFF111111),
        success: Color(0xFF79B597),
        info: Color(0xFF93A6C2),
        danger: Color(0xFFD98577),
      ),
    ),
    light: GwColors.light(
      bandBelow: Color(0xFFB4B4B0),
      bandIn: Color(0xFF161616),
      bandOver: Color(0xFFA6473C),
    ),
    dark: GwColors.dark(
      bandBelow: Color(0xFF6E6E6B),
      bandIn: Color(0xFFEDEDEC),
      bandOver: Color(0xFFD98577),
    ),
  );

  const AppPreset(this.forge, {required this.light, required this.dark});

  final ForgePreset forge;
  final GwColors light;
  final GwColors dark;

  /// The preset release builds use.
  static const shipped = AppPreset.slate;

  ThemeData lightTheme() => _withApp(ForgeTheme.light(forge), light);

  ThemeData darkTheme() => _withApp(ForgeTheme.dark(forge), dark);

  static ThemeData _withApp(ThemeData theme, GwColors colors) =>
      theme.copyWith(extensions: [...theme.extensions.values, colors]);
}

/// The app's own colour roles: the weekly volume band (below 10 sets,
/// 10–20, above 20) and the plates, each in its muted competition colour
/// (the same in every preset). Read with [GwColors.of].
class GwColors extends ThemeExtension<GwColors> {
  const GwColors({
    required this.bandBelow,
    required this.bandIn,
    required this.bandOver,
    required this.plate25,
    required this.plate20,
    required this.plate15,
    required this.plate10,
    required this.plate5,
    required this.plate2p5,
    required this.plate1p25,
  });

  const GwColors.light({
    required Color bandBelow,
    required Color bandIn,
    required Color bandOver,
  }) : this(
         bandBelow: bandBelow,
         bandIn: bandIn,
         bandOver: bandOver,
         plate25: const Color(0xFFA6473C),
         plate20: const Color(0xFF3B5A93),
         plate15: const Color(0xFFB8963E),
         plate10: const Color(0xFF3F7D62),
         plate5: const Color(0xFFD9DCE1),
         plate2p5: const Color(0xFFA6473C),
         plate1p25: const Color(0xFF8B94A3),
       );

  const GwColors.dark({
    required Color bandBelow,
    required Color bandIn,
    required Color bandOver,
  }) : this(
         bandBelow: bandBelow,
         bandIn: bandIn,
         bandOver: bandOver,
         plate25: const Color(0xFFE0907F),
         plate20: const Color(0xFF9DB0D6),
         plate15: const Color(0xFFD8BD72),
         plate10: const Color(0xFF79B597),
         plate5: const Color(0xFFEEF1F5),
         plate2p5: const Color(0xFFE0907F),
         plate1p25: const Color(0xFF6B7689),
       );

  final Color bandBelow;
  final Color bandIn;
  final Color bandOver;

  /// The plates by their kilo weight; pound plates take their kilo match.
  final Color plate25;
  final Color plate20;
  final Color plate15;
  final Color plate10;

  /// White: drawn with a line-strong edge.
  final Color plate5;
  final Color plate2p5;
  final Color plate1p25;

  static GwColors of(BuildContext context) =>
      Theme.of(context).extension<GwColors>()!;

  @override
  GwColors copyWith({
    Color? bandBelow,
    Color? bandIn,
    Color? bandOver,
    Color? plate25,
    Color? plate20,
    Color? plate15,
    Color? plate10,
    Color? plate5,
    Color? plate2p5,
    Color? plate1p25,
  }) => GwColors(
    bandBelow: bandBelow ?? this.bandBelow,
    bandIn: bandIn ?? this.bandIn,
    bandOver: bandOver ?? this.bandOver,
    plate25: plate25 ?? this.plate25,
    plate20: plate20 ?? this.plate20,
    plate15: plate15 ?? this.plate15,
    plate10: plate10 ?? this.plate10,
    plate5: plate5 ?? this.plate5,
    plate2p5: plate2p5 ?? this.plate2p5,
    plate1p25: plate1p25 ?? this.plate1p25,
  );

  @override
  GwColors lerp(GwColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return GwColors(
      bandBelow: mix(bandBelow, other.bandBelow),
      bandIn: mix(bandIn, other.bandIn),
      bandOver: mix(bandOver, other.bandOver),
      plate25: mix(plate25, other.plate25),
      plate20: mix(plate20, other.plate20),
      plate15: mix(plate15, other.plate15),
      plate10: mix(plate10, other.plate10),
      plate5: mix(plate5, other.plate5),
      plate2p5: mix(plate2p5, other.plate2p5),
      plate1p25: mix(plate1p25, other.plate1p25),
    );
  }
}
