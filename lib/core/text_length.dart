// Text lengths are counted in UTF-16 code units, as `String.length` and
// Firestore rules' `size()` count them.

/// [text] without its last character; never half of a surrogate pair.
String dropLastCharacter(String text) {
  if (text.isEmpty) return text;
  final runes = text.runes.toList()..removeLast();
  return String.fromCharCodes(runes);
}

/// [text] cut to at most [max] code units, without splitting a surrogate
/// pair.
String cutToLength(String text, int max) {
  var cut = text;
  while (cut.length > max) {
    cut = dropLastCharacter(cut);
  }
  return cut;
}
