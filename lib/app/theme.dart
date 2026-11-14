import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The app's looks, drawn in GetWorkout Studio. One ships when the app is
/// finished; until then Slate, and debug builds can switch in Profile.
enum AppPreset {
  slate(
    ForgePreset.slate,
    light: GwColors(
      bandBelow: Color(0xFF9AA3B2),
      bandIn: Color(0xFF222B38),
      bandOver: Color(0xFFA6473C),
    ),
    dark: GwColors(
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
    light: GwColors(
      bandBelow: Color(0xFF8FB0F5),
      bandIn: Color(0xFF1F4FD8),
      bandOver: Color(0xFFC2341D),
    ),
    dark: GwColors(
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
    light: GwColors(
      bandBelow: Color(0xFFB4B4B0),
      bandIn: Color(0xFF161616),
      bandOver: Color(0xFFA6473C),
    ),
    dark: GwColors(
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
/// 10–20, above 20). Read with [GwColors.of].
class GwColors extends ThemeExtension<GwColors> {
  const GwColors({
    required this.bandBelow,
    required this.bandIn,
    required this.bandOver,
  });

  final Color bandBelow;
  final Color bandIn;
  final Color bandOver;

  static GwColors of(BuildContext context) =>
      Theme.of(context).extension<GwColors>()!;

  @override
  GwColors copyWith({Color? bandBelow, Color? bandIn, Color? bandOver}) =>
      GwColors(
        bandBelow: bandBelow ?? this.bandBelow,
        bandIn: bandIn ?? this.bandIn,
        bandOver: bandOver ?? this.bandOver,
      );

  @override
  GwColors lerp(GwColors? other, double t) {
    if (other == null) return this;
    return GwColors(
      bandBelow: Color.lerp(bandBelow, other.bandBelow, t)!,
      bandIn: Color.lerp(bandIn, other.bandIn, t)!,
      bandOver: Color.lerp(bandOver, other.bandOver, t)!,
    );
  }
}
