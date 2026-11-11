import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/calories.dart';
import 'calculator_input.dart';

class CaloriesState extends Equatable {
  const CaloriesState({
    this.sex,
    this.activity,
    this.weight = '',
    this.height = '',
    this.age = '',
    this.result,
  });

  final Sex? sex;
  final ActivityLevel? activity;

  /// As typed, in the user's units.
  final String weight;
  final String height;
  final String age;

  /// Null until every input is filled in.
  final Calculation<CalorieEstimate>? result;

  CaloriesState _with({
    Sex? sex,
    ActivityLevel? activity,
    String? weight,
    String? height,
    String? age,
  }) => CaloriesState(
    sex: sex ?? this.sex,
    activity: activity ?? this.activity,
    weight: weight ?? this.weight,
    height: height ?? this.height,
    age: age ?? this.age,
  );

  @override
  List<Object?> get props => [sex, activity, weight, height, age, result];
}

class CaloriesCubit extends Cubit<CaloriesState> {
  CaloriesCubit(
    this._estimate, {
    required this.weightUnit,
    required this.lengthUnit,
  }) : super(const CaloriesState());

  final EstimateCalories _estimate;
  final WeightUnit weightUnit;
  final LengthUnit lengthUnit;

  void sexChanged(Sex sex) => _calculate(state._with(sex: sex));

  void activityChanged(ActivityLevel activity) =>
      _calculate(state._with(activity: activity));

  void weightChanged(String text) => _calculate(state._with(weight: text));

  void heightChanged(String text) => _calculate(state._with(height: text));

  void ageChanged(String text) => _calculate(state._with(age: text));

  void _calculate(CaloriesState inputs) => emit(
    CaloriesState(
      sex: inputs.sex,
      activity: inputs.activity,
      weight: inputs.weight,
      height: inputs.height,
      age: inputs.age,
      result: _result(inputs),
    ),
  );

  Calculation<CalorieEstimate>? _result(CaloriesState inputs) {
    final CaloriesState(:sex, :activity) = inputs;
    final weight = readNumber(inputs.weight);
    final height = readNumber(inputs.height);
    final age = readNumber(inputs.age);
    if (sex == null ||
        activity == null ||
        weight == null ||
        height == null ||
        age == null) {
      return null;
    }
    return _estimate(
      sex: sex,
      activity: activity,
      weightKg: weightUnit.toKg(weight),
      heightCm: lengthUnit.toCm(height),
      ageYears: age,
    );
  }
}
