import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
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
    this.known = const {},
    this.result,
  });

  /// As typed, in the user's units. [bodyFat] is optional.
  final String weight;
  final String height;
  final String bodyFat;

  /// The inputs still holding the known value.
  final Map<CalculatorInput, KnownInput> known;

  /// Null until weight and height are filled in.
  final Calculation<BodyIndices>? result;

  BodyIndicesState _with({
    String? weight,
    String? height,
    String? bodyFat,
    Map<CalculatorInput, KnownInput>? known,
  }) => BodyIndicesState(
    weight: weight ?? this.weight,
    height: height ?? this.height,
    bodyFat: bodyFat ?? this.bodyFat,
    known: known ?? this.known,
  );

  @override
  List<Object?> get props => [weight, height, bodyFat, known, result];
}

enum _Input { weight, height, bodyFat }

/// Starts from what the app knows of the user; a value arriving late fills
/// only the inputs the user has not changed.
class BodyIndicesCubit extends Cubit<BodyIndicesState> {
  BodyIndicesCubit(
    this._calculateIndices,
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues, {
    required this.weightUnit,
    required this.lengthUnit,
  }) : super(const BodyIndicesState()) {
    unawaited(_prefill(getCurrentUser, getKnownValues));
  }

  final CalculateBodyIndices _calculateIndices;
  final WeightUnit weightUnit;
  final LengthUnit lengthUnit;
  final _changed = <_Input>{};

  Future<void> _prefill(
    GetCurrentUser getCurrentUser,
    GetKnownBodyValues getKnownValues,
  ) async {
    final uid = getCurrentUser()?.id;
    if (uid == null) return;
    final known = await getKnownValues(uid);
    if (isClosed) return;
    final knownInputs = {...state.known};
    String? fill(
      _Input input,
      CalculatorInput field,
      String? text, [
      DateTime? date,
    ]) {
      if (_changed.contains(input) || text == null) return null;
      knownInputs[field] = KnownInput(date);
      return text;
    }

    _calculate(
      state._with(
        weight: fill(
          _Input.weight,
          CalculatorInput.bodyWeight,
          knownText(known.weightKg, weightUnit.fromKg),
          known.weightDate,
        ),
        height: fill(
          _Input.height,
          CalculatorInput.height,
          knownText(known.heightCm, lengthUnit.fromCm),
        ),
        bodyFat: fill(
          _Input.bodyFat,
          CalculatorInput.bodyFat,
          knownText(known.bodyFatPercent),
          known.bodyFatDate,
        ),
        known: knownInputs,
      ),
    );
  }

  /// Turns a known [input] into a field the user can change.
  void editKnown(CalculatorInput input) =>
      _calculate(state._with(known: {...state.known}..remove(input)));

  void weightChanged(String text) {
    _changed.add(_Input.weight);
    _calculate(state._with(weight: text));
  }

  void heightChanged(String text) {
    _changed.add(_Input.height);
    _calculate(state._with(height: text));
  }

  void bodyFatChanged(String text) {
    _changed.add(_Input.bodyFat);
    _calculate(state._with(bodyFat: text));
  }

  void _calculate(BodyIndicesState inputs) {
    final weight = readNumber(inputs.weight);
    final height = readNumber(inputs.height);
    emit(
      BodyIndicesState(
        weight: inputs.weight,
        height: inputs.height,
        bodyFat: inputs.bodyFat,
        known: inputs.known,
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
