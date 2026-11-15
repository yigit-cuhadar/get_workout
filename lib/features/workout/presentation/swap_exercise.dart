import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../exercises/domain/exercise.dart';

/// Asks which exercise replaces [exerciseId], [logged] of whose working
/// sets and [warmups] of whose warm-ups are done (the picker's Swap form
/// says they stay); null when none is picked.
/// [picker] is where the page's exercise picker opens.
// Opens the plain single-choice picker until the picker's Swap form lands.
Future<String?> pickSwap(
  BuildContext context, {
  required String exerciseId,
  required int logged,
  required int warmups,
  required String Function({required int max, required bool multiple}) picker,
}) async {
  final picked = await context.push<List<Exercise>>(
    picker(max: 1, multiple: false),
  );
  return picked?.firstOrNull?.id;
}
