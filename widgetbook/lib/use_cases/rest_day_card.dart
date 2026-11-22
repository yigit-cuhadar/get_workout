import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/today/presentation/widgets/rest_day_card.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _card({required int? steps, bool locked = false}) =>
    SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.md),
      child: RestDayCard(
        next: 'Pull, Mon, Nov 16',
        nextDay: 'Pull',
        steps: steps,
        goal: 10000,
        onSteps: () {},
        onLogCardio: () {},
        onStartEarly: () {},
        locked: locked,
      ),
    );

@widgetbook.UseCase(name: 'Walk toward the goal', type: RestDayCard)
Widget restDayWalk(BuildContext context) => _card(
  steps: context.knobs.int.slider(
    label: 'Steps today',
    initialValue: 6240,
    max: 9999,
  ),
);

@widgetbook.UseCase(name: 'No step access', type: RestDayCard)
Widget restDayNoSteps(BuildContext context) => _card(steps: null);

@widgetbook.UseCase(name: 'Goal reached', type: RestDayCard)
Widget restDayGoal(BuildContext context) => _card(steps: 10240);

@widgetbook.UseCase(name: 'Locked next day', type: RestDayCard)
Widget restDayLocked(BuildContext context) => _card(steps: 6240, locked: true);
