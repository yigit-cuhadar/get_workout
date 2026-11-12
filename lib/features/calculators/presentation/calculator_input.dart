import 'package:forge_core/forge_core.dart';

/// The value of a number field: null while empty, NaN when it is not a
/// number, which every range check rejects.
double? readNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', '.')) ?? double.nan;
}

/// Like [readNumber] for counts; anything but a whole number reads as -1,
/// below every count range.
int? readCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed) ?? -1;
}

/// A known metric value as field text after [convert] to the user's unit,
/// to one decimal without trailing zeros; null when unknown.
String? knownText(double? metric, [double Function(double)? convert]) {
  if (metric == null) return null;
  final text = (convert?.call(metric) ?? metric).toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// An input still holding the value the app knows, shown as that value
/// until the user taps it to edit. [date] is when it was recorded, null for
/// a value that does not change over time.
class KnownInput extends Equatable {
  const KnownInput([this.date]);

  final DateTime? date;

  @override
  List<Object?> get props => [date];
}
