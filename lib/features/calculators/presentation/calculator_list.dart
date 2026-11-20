import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';

/// One calculator: which, its name, what it works out, its route and
/// whether it is for training rather than the body.
typedef CalculatorEntry = ({
  Calculator calculator,
  String title,
  String subtitle,
  String route,
  bool training,
});

/// Every calculator, in the order the Calculators page and Today list them.
List<CalculatorEntry> calculatorsOf(AppLocalizations l10n) => [
  (
    calculator: Calculator.calories,
    title: l10n.calcCaloriesTitle,
    subtitle: l10n.calcCaloriesSubtitle,
    route: Routes.calories,
    training: false,
  ),
  (
    calculator: Calculator.bodyFat,
    title: l10n.calcBodyFatTitle,
    subtitle: l10n.calcBodyFatSubtitle,
    route: Routes.bodyFat,
    training: false,
  ),
  (
    calculator: Calculator.oneRepMax,
    title: l10n.calcOneRepMaxTitle,
    subtitle: l10n.calcOneRepMaxSubtitle,
    route: Routes.oneRepMax,
    training: true,
  ),
  (
    calculator: Calculator.plates,
    title: l10n.calcPlatesTitle,
    subtitle: l10n.calcPlatesSubtitle,
    route: Routes.plates,
    training: true,
  ),
  (
    calculator: Calculator.macros,
    title: l10n.calcMacrosTitle,
    subtitle: l10n.calcMacrosSubtitle,
    route: Routes.macros,
    training: false,
  ),
  (
    calculator: Calculator.bodyIndices,
    title: l10n.calcBodyIndicesTitle,
    subtitle: l10n.calcBodyIndicesSubtitle,
    route: Routes.bodyIndices,
    training: false,
  ),
];

/// Opens [entry]'s calculator: a `calculator_use`.
void openCalculator(BuildContext context, CalculatorEntry entry) {
  unawaited(context.read<Analytics>().calculatorUse(entry.calculator));
  context.go(entry.route);
}
