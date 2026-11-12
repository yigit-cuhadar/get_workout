import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/macros.dart';
import 'calculator_input.dart';

class MacrosState extends Equatable {
  const MacrosState({
    this.calories = '',
    this.weight = '',
    this.proteinGPerKg = defaultProteinGPerKg,
    this.fatPercent = defaultFatPercent,
    this.known = const {},
    this.result,
  });

  /// As typed; [weight] in the user's weight unit.
  final String calories;
  final String weight;
  final double proteinGPerKg;
  final double fatPercent;

  /// Holds the weight while it is the known one.
  final Map<CalculatorInput, KnownInput> known;

  /// Null until calories and weight are filled in.
  final Calculation<Macros>? result;

  MacrosState _with({
    String? calories,
    String? weight,
    double? proteinGPerKg,
    double? fatPercent,
    Map<CalculatorInput, KnownInput>? known,
  }) => MacrosState(
    calories: calories ?? this.calories,
    weight: weight ?? this.weight,
    proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
    fatPercent: fatPercent ?? this.fatPercent,
    known: known ?? this.known,
  );

  @override
  List<Object?> get props => [
    calories,
    weight,
    proteinGPerKg,
    fatPercent,
    known,
    result,
  ];
}

/// Starts from the user's known weight, unless they changed it before it
/// arrived. Calories are not known: they depend on the target chosen.
class MacrosCubit extends Cubit<MacrosState> {
  MacrosCubit(
    this._split,
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues, {
    required this.weightUnit,
  }) : super(const MacrosState()) {
    unawaited(_prefill(getCurrentUser, getKnownValues));
  }

  final SplitMacros _split;
  final WeightUnit weightUnit;
  var _weightChanged = false;

  Future<void> _prefill(
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues,
  ) async {
    final uid = getCurrentUser()?.id;
    if (uid == null) return;
    final known = await getKnownValues(uid);
    if (isClosed || _weightChanged) return;
    final weight = knownText(known.weightKg, weightUnit.fromKg);
    if (weight == null) return;
    _calculate(
      state._with(
        weight: weight,
        known: {CalculatorInput.bodyWeight: KnownInput(known.weightDate)},
      ),
    );
  }

  /// Turns a known [input] into a field the user can change.
  void editKnown(CalculatorInput input) =>
      _calculate(state._with(known: {...state.known}..remove(input)));

  void caloriesChanged(String text) => _calculate(state._with(calories: text));

  void weightChanged(String text) {
    _weightChanged = true;
    _calculate(state._with(weight: text));
  }

  void proteinChanged(double gPerKg) =>
      _calculate(state._with(proteinGPerKg: gPerKg));

  void fatChanged(double percent) =>
      _calculate(state._with(fatPercent: percent));

  void _calculate(MacrosState inputs) {
    final calories = readNumber(inputs.calories);
    final weight = readNumber(inputs.weight);
    emit(
      MacrosState(
        calories: inputs.calories,
        weight: inputs.weight,
        proteinGPerKg: inputs.proteinGPerKg,
        fatPercent: inputs.fatPercent,
        known: inputs.known,
        result: calories == null || weight == null
            ? null
            : _split(
                calories: calories,
                weightKg: weightUnit.toKg(weight),
                proteinGPerKg: inputs.proteinGPerKg,
                fatPercent: inputs.fatPercent,
              ),
      ),
    );
  }
}
