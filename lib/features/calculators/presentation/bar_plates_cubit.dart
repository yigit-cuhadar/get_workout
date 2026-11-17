import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/calculation.dart';
import '../domain/calculators_usecases.dart';
import '../../../core/number_text.dart';

/// Checks and plate lists for the Bar and plates page; the plates are the
/// user's, from their settings, kept current through [platesChanged].
/// Edits are saved through `SettingsCubit`.
class BarPlatesCubit extends Cubit<List<Plate>> {
  BarPlatesCubit(
    this._checkBarWeight,
    this._checkPlate, {
    required this.weightUnit,
    required List<Plate> plates,
  }) : super(plates);

  final CheckBarWeight _checkBarWeight;
  final CheckPlate _checkPlate;
  final WeightUnit weightUnit;

  void platesChanged(List<Plate> plates) => emit(plates);

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
    for (final other in state)
      if (other != plate) other,
  ];

  /// Plates typed in pounds are stored with full precision in kg.
  static bool _sameWeight(double a, double b) => (a - b).abs() < 0.001;
}
