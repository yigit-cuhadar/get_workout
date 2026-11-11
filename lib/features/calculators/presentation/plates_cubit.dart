import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../domain/plates.dart';
import 'calculator_input.dart';

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

/// The plate calculator, plus checks for the bar and plate editor. Edited
/// equipment is saved through `SettingsCubit` and comes back through
/// [equipmentChanged].
class PlatesCubit extends Cubit<PlatesState> {
  PlatesCubit(
    this._loadPlates,
    this._checkBarWeight,
    this._checkPlate, {
    required this.weightUnit,
    required double barKg,
    required List<Plate> plates,
  }) : super(PlatesState(barKg: barKg, plates: plates));

  final LoadPlates _loadPlates;
  final CheckBarWeight _checkBarWeight;
  final CheckPlate _checkPlate;
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

  /// A bar weight typed in the editor, in kg; null while empty.
  Calculation<double>? checkBar(String text) {
    final weight = readNumber(text);
    return weight == null ? null : _checkBarWeight(weightUnit.toKg(weight));
  }

  /// A plate typed in the editor, in kg; null while a field is empty.
  Calculation<Plate>? checkPlate(String weightText, String pairsText) {
    final weight = readNumber(weightText);
    final pairs = readCount(pairsText);
    if (weight == null || pairs == null) return null;
    return _checkPlate(weightKg: weightUnit.toKg(weight), pairs: pairs);
  }

  /// The current plates with [plate] added, or replacing [replacing] or a
  /// plate of the same weight. Largest first.
  List<Plate> withPlate(Plate plate, {Plate? replacing}) => [
    ...withoutPlate(replacing)
        .where((other) => !_sameWeight(other.weightKg, plate.weightKg)),
    plate,
  ]..sort((a, b) => b.weightKg.compareTo(a.weightKg));

  List<Plate> withoutPlate(Plate? plate) => [
    for (final other in state.plates)
      if (other != plate) other,
  ];

  /// Plates typed in pounds are stored with full precision in kg.
  static bool _sameWeight(double a, double b) => (a - b).abs() < 0.001;
}
