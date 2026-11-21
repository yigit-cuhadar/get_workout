import 'package:flutter/widgets.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../features/exercises/domain/vocabulary.dart';
import 'admin_text.dart';

/// The status of a piece of content as a tag: live in the record tint,
/// draft in the category tint, retired plain grey.
class StatusTag extends StatelessWidget {
  const StatusTag(this.status, {super.key});

  final ExerciseStatus status;

  @override
  Widget build(BuildContext context) => ForgeTag(
    codeLabel(status),
    kind: switch (status) {
      ExerciseStatus.live => ForgeTagKind.record,
      ExerciseStatus.draft => ForgeTagKind.category,
      ExerciseStatus.retired => ForgeTagKind.neutral,
    },
  );
}
