import 'user_settings.dart';

/// The kg to store for lifted weights typed into fields that show
/// [WeightUnitConversion.shown] numbers.
///
/// Each field, named by a key, remembers its weight from before its first
/// edit, so typing back the number that weight was shown as (80 kg shown as
/// 176 lb) stores it unchanged, however the text got there; any other number
/// is stored as typed, converted to kg. Callers [clear] it whenever fields
/// may move to other keys.
class RetypedWeights<K> {
  final _before = <K, double>{};

  /// What to store for [text] typed in [unit] into field [key], which holds
  /// [current]; null for blank or unreadable text.
  double? kg(K key, String text, WeightUnit unit, double? current) {
    if (current != null) _before.putIfAbsent(key, () => current);
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite) return null;
    final before = _before[key];
    if (before != null && value == unit.shownFromKg(before)) return before;
    return unit.toKg(value);
  }

  void clear() => _before.clear();
}
