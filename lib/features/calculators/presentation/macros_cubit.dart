import 'package:flutter_bloc/flutter_bloc.dart';
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
    this.result,
  });

  /// As typed; [weight] in the user's weight unit.
  final String calories;
  final String weight;
  final double proteinGPerKg;
  final double fatPercent;

  /// Null until calories and weight are filled in.
  final Calculation<Macros>? result;

  MacrosState _with({
    String? calories,
    String? weight,
    double? proteinGPerKg,
    double? fatPercent,
  }) => MacrosState(
    calories: calories ?? this.calories,
    weight: weight ?? this.weight,
    proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
    fatPercent: fatPercent ?? this.fatPercent,
  );

  @override
  List<Object?> get props => [
    calories,
    weight,
    proteinGPerKg,
    fatPercent,
    result,
  ];
}

class MacrosCubit extends Cubit<MacrosState> {
  MacrosCubit(this._split, {required this.weightUnit})
    : super(const MacrosState());

  final SplitMacros _split;
  final WeightUnit weightUnit;

  void caloriesChanged(String text) => _calculate(state._with(calories: text));

  void weightChanged(String text) => _calculate(state._with(weight: text));

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
