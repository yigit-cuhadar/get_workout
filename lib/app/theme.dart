import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The app's look, drawn in GetWorkout Studio: Slate ships. There is no
/// runtime switch; users only choose Light, Dark or System.
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
  );

  const AppPreset(this.forge, {required this.light, required this.dark});

  final ForgePreset forge;
  final GwColors light;
  final GwColors dark;

  /// The preset the app uses.
  static const shipped = AppPreset.slate;

  ThemeData lightTheme() => _withApp(ForgeTheme.light(forge), light);

  ThemeData darkTheme() => _withApp(ForgeTheme.dark(forge), dark);

  static ThemeData _withApp(ThemeData theme, GwColors colors) =>
      theme.copyWith(extensions: [...theme.extensions.values, colors]);
}

/// The app's own colour roles: the weekly volume band (below 10 sets,
/// 10–20, above 20) and the plates, each in its muted competition colour.
/// Read with [GwColors.of].
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
