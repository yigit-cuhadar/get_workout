import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// GetWorkout's mark, the logo's two letters, in the colour of the tile it
/// sits on; as tall as a capital at [size] (or the tile's text size).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size});

  final double? size;

  static const asset = 'assets/images/app_mark.png';

  /// The letters' height against the font size they stand in for.
  static const _capHeight = 0.8;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final fontSize = size ?? style.fontSize ?? 14;
    return Image.asset(
      asset,
      height: fontSize * _capHeight,
      color: style.color,
      semanticLabel: AppLocalizations.of(context).appMark,
    );
  }
}
