import 'package:forge_core/forge_core.dart';

/// A known metric value as field text after [convert] to the user's unit,
/// to one decimal without trailing zeros; null when unknown.
String? knownText(double? metric, [double Function(double)? convert]) {
  if (metric == null) return null;
  final text = (convert?.call(metric) ?? metric).toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// An input still holding the value the app knows, until the user sets
/// it. [date] is when it was recorded, null for a value that does not
/// change over time.
class KnownInput extends Equatable {
  const KnownInput([this.date]);

  final DateTime? date;

  @override
  List<Object?> get props => [date];
}
