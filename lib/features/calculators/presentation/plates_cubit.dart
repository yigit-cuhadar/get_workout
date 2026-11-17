import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/plates.dart';
import '../../../core/number_text.dart';

class PlatesState extends Equatable {
  const PlatesState({
    required this.barKg,
    required this.plates,
    this.target = '',
    this.result,
  });

  /// The user's equipment, from their settings.
  final double barKg;
  final List<Plate> plates;

  /// As typed, in the user's weight unit.
  final String target;

  /// Null until a target is filled in.
  final Calculation<PlateLoad>? result;

  @override
  List<Object?> get props => [barKg, plates, target, result];
}

/// The plate calculator. The equipment comes from the user's settings and
/// changes through [equipmentChanged].
class PlatesCubit extends Cubit<PlatesState> {
  PlatesCubit(
    this._loadPlates, {
    required this.weightUnit,
    required double barKg,
    required List<Plate> plates,
  }) : super(PlatesState(barKg: barKg, plates: plates));

  final LoadPlates _loadPlates;
  final WeightUnit weightUnit;

  void targetChanged(String text) =>
      _calculate(text, state.barKg, state.plates);

  void equipmentChanged(double barKg, List<Plate> plates) =>
      _calculate(state.target, barKg, plates);

  void _calculate(String targetText, double barKg, List<Plate> plates) {
    final target = readNumber(targetText);
    emit(
      PlatesState(
        barKg: barKg,
        plates: plates,
        target: targetText,
        result: target == null
            ? null
            : _loadPlates(
                targetKg: weightUnit.toKg(target),
                barKg: barKg,
                plates: plates,
              ),
      ),
    );
  }
}
