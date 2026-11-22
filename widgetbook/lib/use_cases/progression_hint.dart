import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/progression_hint.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Try more weight', type: ProgressionHint)
Widget progressionHint(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 20),
  child: ProgressionHint(
    text: context.knobs.string(
      label: 'Text',
      initialValue: 'You hit 8 reps last time. Try 82.5 kg.',
    ),
    onTap: () {},
  ),
);
