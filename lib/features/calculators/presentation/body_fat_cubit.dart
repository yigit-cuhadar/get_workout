import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/calories.dart';
import '../domain/known_body_values.dart';
import 'calculator_input.dart';

class BodyFatState extends Equatable {
  const BodyFatState({
    this.sex,
    this.height = '',
    this.neck = '',
    this.waist = '',
    this.hip = '',
    this.known = const {},
    this.result,
  });

  final Sex? sex;

  /// As typed, in the user's length unit. [hip] is used for women only.
  final String height;
  final String neck;
  final String waist;
  final String hip;

  /// The length inputs still holding the known value.
  final Map<CalculatorInput, KnownInput> known;

  /// Body fat %; null until every needed input is filled in.
  final Calculation<double>? result;

  BodyFatState _with({
    Sex? sex,
    String? height,
    String? neck,
    String? waist,
    String? hip,
    Map<CalculatorInput, KnownInput>? known,
  }) => BodyFatState(
    sex: sex ?? this.sex,
    height: height ?? this.height,
    neck: neck ?? this.neck,
    waist: waist ?? this.waist,
    hip: hip ?? this.hip,
    known: known ?? this.known,
  );

  @override
  List<Object?> get props => [sex, height, neck, waist, hip, known, result];
}

/// Starts from what the app knows of the user; a value arriving late fills
/// only the inputs the user has not changed or started editing. The waist
/// follows the selected sex: the abdomen for men, the waist for women.
class BodyFatCubit extends Cubit<BodyFatState> {
  BodyFatCubit(
    this._estimate,
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues, {
    required this.lengthUnit,
  }) : super(const BodyFatState()) {
    unawaited(_prefill(getCurrentUser, getKnownValues));
  }

  final EstimateBodyFat _estimate;
  final LengthUnit lengthUnit;
  final _changed = <CalculatorInput>{};
  var _sexChanged = false;
  KnownBodyValues? _known;

  Future<void> _prefill(
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues,
  ) async {
    final uid = getCurrentUser()?.id;
    if (uid == null) return;
    final known = await getKnownValues(uid);
    if (isClosed) return;
    _known = known;
    final knownInputs = {...state.known};
    String? length(CalculatorInput input, double? cm, [DateTime? date]) {
      if (_changed.contains(input) || cm == null) return null;
      knownInputs[input] = KnownInput(date);
      return knownText(cm, lengthUnit.fromCm);
    }

    final sex = _sexChanged ? state.sex : known.sex;
    final waist = sex == null ? null : known.navyWaistFor(sex);
    _calculate(
      state._with(
        sex: sex,
        height: length(CalculatorInput.height, known.heightCm),
        neck: length(CalculatorInput.neck, known.neckCm, known.neckDate),
        waist: length(CalculatorInput.waist, waist?.cm, waist?.date),
        hip: length(CalculatorInput.hip, known.hipCm, known.hipDate),
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

  /// An untouched waist becomes the known measurement for [sex], or empty.
  void sexChanged(Sex sex) {
    _sexChanged = true;
    final known = _known;
    if (known == null || _changed.contains(CalculatorInput.waist)) {
      _calculate(state._with(sex: sex));
      return;
    }
    final waist = known.navyWaistFor(sex);
    final knownInputs = {...state.known}..remove(CalculatorInput.waist);
    if (waist != null) {
      knownInputs[CalculatorInput.waist] = KnownInput(waist.date);
    }
    _calculate(
      state._with(
        sex: sex,
        waist: knownText(waist?.cm, lengthUnit.fromCm) ?? '',
        known: knownInputs,
      ),
    );
  }

  void heightChanged(String text) {
    _changed.add(CalculatorInput.height);
    _calculate(state._with(height: text));
  }

  void neckChanged(String text) {
    _changed.add(CalculatorInput.neck);
    _calculate(state._with(neck: text));
  }

  void waistChanged(String text) {
    _changed.add(CalculatorInput.waist);
    _calculate(state._with(waist: text));
  }

  void hipChanged(String text) {
    _changed.add(CalculatorInput.hip);
    _calculate(state._with(hip: text));
  }

  void _calculate(BodyFatState inputs) => emit(
    BodyFatState(
      sex: inputs.sex,
      height: inputs.height,
      neck: inputs.neck,
      waist: inputs.waist,
      hip: inputs.hip,
      known: inputs.known,
      result: _result(inputs),
    ),
  );

  Calculation<double>? _result(BodyFatState inputs) {
    final sex = inputs.sex;
    final height = readNumber(inputs.height);
    final neck = readNumber(inputs.neck);
    final waist = readNumber(inputs.waist);
    final hip = readNumber(inputs.hip);
    if (sex == null || height == null || neck == null || waist == null) {
      return null;
    }
    if (sex == Sex.female && hip == null) return null;
    return _estimate(
      sex: sex,
      heightCm: lengthUnit.toCm(height),
      neckCm: lengthUnit.toCm(neck),
      waistCm: lengthUnit.toCm(waist),
      hipCm: hip == null ? null : lengthUnit.toCm(hip),
    );
  }
}
