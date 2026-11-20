import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// get_it throws at runtime when a factory registered with a non-nullable
/// parameter is resolved without it, and page tests register their own
/// factories, so only the source shows such a call.
void main() {
  test('every parameterised factory gets its required parameters', () {
    final sources = {
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          file.path: file.readAsStringSync(),
    };
    final registration = RegExp(
      r'registerFactoryParam<\s*(\w+)\s*,\s*([\w?]+(?:<[^>]*>)?\??)\s*,'
      r'\s*([\w?]+(?:<[^>]*>)?\??)\s*>\(',
    );
    bool required(String type) =>
        type != 'void' && type != 'dynamic' && !type.endsWith('?');

    final missing = <String>[];
    for (final source in sources.values) {
      for (final match in registration.allMatches(source)) {
        final name = match.group(1)!;
        final needs = [
          if (required(match.group(2)!)) 'param1',
          if (required(match.group(3)!)) 'param2',
        ];
        final call = RegExp('sl<$name>\\(([^;]*?)\\)');
        for (final MapEntry(key: path, value: other) in sources.entries) {
          for (final use in call.allMatches(other)) {
            for (final param in needs) {
              if (!use.group(1)!.contains(param)) {
                final line = '\n'.allMatches(other.substring(0, use.start));
                missing.add('$path:${line.length + 1} $name without $param');
              }
            }
          }
        }
      }
    }
    expect(missing, isEmpty);
  });
}
