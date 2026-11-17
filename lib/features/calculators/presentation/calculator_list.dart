import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

/// One calculator: its name, what it works out, its route and whether it is
/// for training rather than the body.
typedef CalculatorEntry = ({
  String title,
  String subtitle,
  String route,
  bool training,
});

/// Every calculator, in the order the Calculators page and Today list them.
List<CalculatorEntry> calculatorsOf(AppLocalizations l10n) => [
  (
    title: l10n.calcCaloriesTitle,
    subtitle: l10n.calcCaloriesSubtitle,
    route: Routes.calories,
    training: false,
  ),
  (
    title: l10n.calcBodyFatTitle,
    subtitle: l10n.calcBodyFatSubtitle,
    route: Routes.bodyFat,
    training: false,
  ),
  (
    title: l10n.calcOneRepMaxTitle,
    subtitle: l10n.calcOneRepMaxSubtitle,
    route: Routes.oneRepMax,
    training: true,
  ),
  (
    title: l10n.calcPlatesTitle,
    subtitle: l10n.calcPlatesSubtitle,
    route: Routes.plates,
    training: true,
  ),
  (
    title: l10n.calcMacrosTitle,
    subtitle: l10n.calcMacrosSubtitle,
    route: Routes.macros,
    training: false,
  ),
  (
    title: l10n.calcBodyIndicesTitle,
    subtitle: l10n.calcBodyIndicesSubtitle,
    route: Routes.bodyIndices,
    training: false,
  ),
];
