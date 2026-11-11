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
