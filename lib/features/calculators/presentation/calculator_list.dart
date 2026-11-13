import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

/// One calculator: its name, what it works out and its route.
typedef CalculatorEntry = ({String title, String subtitle, String route});

/// Every calculator, in the order the Calculators page and Today list them.
List<CalculatorEntry> calculatorsOf(AppLocalizations l10n) => [
  (
    title: l10n.calcCaloriesTitle,
    subtitle: l10n.calcCaloriesSubtitle,
    route: Routes.calories,
  ),
  (
    title: l10n.calcBodyFatTitle,
    subtitle: l10n.calcBodyFatSubtitle,
    route: Routes.bodyFat,
  ),
  (
    title: l10n.calcOneRepMaxTitle,
    subtitle: l10n.calcOneRepMaxSubtitle,
    route: Routes.oneRepMax,
  ),
  (
    title: l10n.calcPlatesTitle,
    subtitle: l10n.calcPlatesSubtitle,
    route: Routes.plates,
  ),
  (
    title: l10n.calcMacrosTitle,
    subtitle: l10n.calcMacrosSubtitle,
    route: Routes.macros,
  ),
  (
    title: l10n.calcBodyIndicesTitle,
    subtitle: l10n.calcBodyIndicesSubtitle,
    route: Routes.bodyIndices,
  ),
];
