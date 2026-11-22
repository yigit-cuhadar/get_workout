import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// GetWorkout's mark, its two letters, in the colour of the tile it sits
/// on; [size] when the tile does not set one.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) => Text(
    AppLocalizations.of(context).appMark,
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
  );
}
