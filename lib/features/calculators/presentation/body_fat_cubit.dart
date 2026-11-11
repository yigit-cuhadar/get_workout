import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/calories.dart';
import 'calculator_input.dart';

class BodyFatState extends Equatable {
  const BodyFatState({
    this.sex,
    this.height = '',
    this.neck = '',
    this.waist = '',
    this.hip = '',
    this.result,
  });

  final Sex? sex;

  /// As typed, in the user's length unit. [hip] is used for women only.
  final String height;
  final String neck;
  final String waist;
  final String hip;

  /// Body fat %; null until every needed input is filled in.
  final Calculation<double>? result;

  BodyFatState _with({
    Sex? sex,
    String? height,
    String? neck,
    String? waist,
    String? hip,
  }) => BodyFatState(
    sex: sex ?? this.sex,
    height: height ?? this.height,
    neck: neck ?? this.neck,
    waist: waist ?? this.waist,
    hip: hip ?? this.hip,
  );

  @override
  List<Object?> get props => [sex, height, neck, waist, hip, result];
}

class BodyFatCubit extends Cubit<BodyFatState> {
  BodyFatCubit(this._estimate, {required this.lengthUnit})
    : super(const BodyFatState());

  final EstimateBodyFat _estimate;
  final LengthUnit lengthUnit;

  void sexChanged(Sex sex) => _calculate(state._with(sex: sex));

  void heightChanged(String text) => _calculate(state._with(height: text));

  void neckChanged(String text) => _calculate(state._with(neck: text));

  void waistChanged(String text) => _calculate(state._with(waist: text));

  void hipChanged(String text) => _calculate(state._with(hip: text));

  void _calculate(BodyFatState inputs) => emit(
    BodyFatState(
      sex: inputs.sex,
      height: inputs.height,
      neck: inputs.neck,
      waist: inputs.waist,
      hip: inputs.hip,
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
