import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
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
    this.known = const {},
    this.result,
  });

  final Sex? sex;
  final ActivityLevel? activity;

  /// As typed, in the user's units.
  final String weight;
  final String height;
  final String age;

  /// The number inputs still holding the known value.
  final Map<CalculatorInput, KnownInput> known;

  /// Null until every input is filled in.
  final Calculation<CalorieEstimate>? result;

  CaloriesState _with({
    Sex? sex,
    ActivityLevel? activity,
    String? weight,
    String? height,
    String? age,
    Map<CalculatorInput, KnownInput>? known,
  }) => CaloriesState(
    sex: sex ?? this.sex,
    activity: activity ?? this.activity,
    weight: weight ?? this.weight,
    height: height ?? this.height,
    age: age ?? this.age,
    known: known ?? this.known,
  );

  @override
  List<Object?> get props => [
    sex,
    activity,
    weight,
    height,
    age,
    known,
    result,
  ];
}

/// Starts from what the app knows of the user; a value arriving late fills
/// only the inputs the user has not changed or started editing.
class CaloriesCubit extends Cubit<CaloriesState> {
  CaloriesCubit(
    this._estimate,
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues, {
    required this.weightUnit,
    required this.lengthUnit,
  }) : super(const CaloriesState()) {
    unawaited(_prefill(getCurrentUser, getKnownValues));
  }

  final EstimateCalories _estimate;
  final WeightUnit weightUnit;
  final LengthUnit lengthUnit;
  final _changed = <CalculatorInput>{};
  var _sexChanged = false;
  var _activityChanged = false;

  Future<void> _prefill(
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues,
  ) async {
    final uid = getCurrentUser()?.id;
    if (uid == null) return;
    final known = await getKnownValues(uid);
    if (isClosed) return;
    final knownInputs = {...state.known};
    String? number(CalculatorInput input, String? text, [DateTime? date]) {
      if (_changed.contains(input) || text == null) return null;
      knownInputs[input] = KnownInput(date);
      return text;
    }

    _calculate(
      state._with(
        sex: _sexChanged ? null : known.sex,
        activity: _activityChanged ? null : known.activity,
        weight: number(
          CalculatorInput.bodyWeight,
          knownText(known.weightKg, weightUnit.fromKg),
          known.weightDate,
        ),
        height: number(
          CalculatorInput.height,
          knownText(known.heightCm, lengthUnit.fromCm),
        ),
        age: number(CalculatorInput.age, known.ageYears?.toString()),
        known: knownInputs,
      ),
    );
  }

  /// The user started editing [input]: it is a plain field from now on,
  /// which known values leave alone.
  void edit(CalculatorInput input) {
    _changed.add(input);
    _calculate(state._with(known: {...state.known}..remove(input)));
  }

  void sexChanged(Sex sex) {
    _sexChanged = true;
    _calculate(state._with(sex: sex));
  }

  void activityChanged(ActivityLevel activity) {
    _activityChanged = true;
    _calculate(state._with(activity: activity));
  }

  void weightChanged(String text) {
    _changed.add(CalculatorInput.bodyWeight);
    _calculate(state._with(weight: text));
  }

  void heightChanged(String text) {
    _changed.add(CalculatorInput.height);
    _calculate(state._with(height: text));
  }

  void ageChanged(String text) {
    _changed.add(CalculatorInput.age);
    _calculate(state._with(age: text));
  }

  void _calculate(CaloriesState inputs) => emit(
    CaloriesState(
      sex: inputs.sex,
      activity: inputs.activity,
      weight: inputs.weight,
      height: inputs.height,
      age: inputs.age,
      known: inputs.known,
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
