import 'package:flutter/services.dart';

import 'text_length.dart';

/// Cuts text to [max] code units, counted like validation counts them;
/// [LengthLimitingTextInputFormatter] counts characters, so a text it
/// accepts could still be too long.
TextInputFormatter maxLengthFormatter(int max) =>
    TextInputFormatter.withFunction((_, value) {
      if (value.text.length <= max) return value;
      final text = cutToLength(value.text, max);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
