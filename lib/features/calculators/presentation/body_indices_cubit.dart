import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/body_indices.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import 'calculator_input.dart';

class BodyIndicesState extends Equatable {
  const BodyIndicesState({
    this.weight = '',
    this.height = '',
    this.bodyFat = '',
    this.result,
  });

  /// As typed, in the user's units. [bodyFat] is optional.
  final String weight;
  final String height;
  final String bodyFat;

  /// Null until weight and height are filled in.
  final Calculation<BodyIndices>? result;

  BodyIndicesState _with({String? weight, String? height, String? bodyFat}) =>
      BodyIndicesState(
        weight: weight ?? this.weight,
        height: height ?? this.height,
        bodyFat: bodyFat ?? this.bodyFat,
      );

  @override
  List<Object?> get props => [weight, height, bodyFat, result];
}

class BodyIndicesCubit extends Cubit<BodyIndicesState> {
  BodyIndicesCubit(
    this._calculateIndices, {
    required this.weightUnit,
    required this.lengthUnit,
  }) : super(const BodyIndicesState());

  final CalculateBodyIndices _calculateIndices;
  final WeightUnit weightUnit;
  final LengthUnit lengthUnit;

  void weightChanged(String text) => _calculate(state._with(weight: text));

  void heightChanged(String text) => _calculate(state._with(height: text));

  void bodyFatChanged(String text) => _calculate(state._with(bodyFat: text));

  void _calculate(BodyIndicesState inputs) {
    final weight = readNumber(inputs.weight);
    final height = readNumber(inputs.height);
    emit(
      BodyIndicesState(
        weight: inputs.weight,
        height: inputs.height,
        bodyFat: inputs.bodyFat,
        result: weight == null || height == null
            ? null
            : _calculateIndices(
                weightKg: weightUnit.toKg(weight),
                heightCm: lengthUnit.toCm(height),
                bodyFatPercent: readNumber(inputs.bodyFat),
              ),
      ),
    );
  }
}
