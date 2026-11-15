import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../exercises/domain/exercise.dart';

/// Opens [picker]'s page for one exercise in place of [exerciseId] (null
/// when that exercise is no longer in the library); the picked exercise,
/// or null when none is picked.
// The exercise picker's own pickReplacement (its Replace form) takes this
// place once both branches are merged.
Future<Exercise?> pickReplacement(
  BuildContext context, {
  required String? exerciseId,
  required String Function({required int max, required bool multiple}) picker,
}) async {
  final picked = await context.push<List<Exercise>>(
    picker(max: 1, multiple: false),
  );
  return picked?.firstOrNull;
}
