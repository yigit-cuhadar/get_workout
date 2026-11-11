import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/one_rep_max.dart';
import 'calculator_input.dart';

class OneRepMaxState extends Equatable {
  const OneRepMaxState({this.weight = '', this.reps = '', this.result});

  /// As typed; [weight] in the user's weight unit.
  final String weight;
  final String reps;

  /// Null until both inputs are filled in.
  final Calculation<OneRepMax>? result;

  @override
  List<Object?> get props => [weight, reps, result];
}

class OneRepMaxCubit extends Cubit<OneRepMaxState> {
  OneRepMaxCubit(this._estimate, {required this.weightUnit})
    : super(const OneRepMaxState());

  final EstimateOneRepMax _estimate;
  final WeightUnit weightUnit;

  /// The smallest step a bar is loaded in: 2.5 kg or 5 lb.
  double get _incrementKg => switch (weightUnit) {
    WeightUnit.kg => 2.5,
    WeightUnit.lb => WeightUnit.lb.toKg(5),
  };

  void weightChanged(String text) => _calculate(text, state.reps);

  void repsChanged(String text) => _calculate(state.weight, text);

  void _calculate(String weightText, String repsText) {
    final weight = readNumber(weightText);
    final reps = readCount(repsText);
    emit(
      OneRepMaxState(
        weight: weightText,
        reps: repsText,
        result: weight == null || reps == null
            ? null
            : _estimate(
                weightKg: weightUnit.toKg(weight),
                reps: reps,
                incrementKg: _incrementKg,
              ),
      ),
    );
  }
}
