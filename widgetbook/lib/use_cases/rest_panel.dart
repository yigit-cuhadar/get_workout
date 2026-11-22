import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/rest_panel.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

/// The panel at the bottom of the screen, on surface.
Widget _panel(BuildContext context, Widget child) => Column(
  mainAxisAlignment: MainAxisAlignment.end,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    ColoredBox(color: ForgeStyle.of(context).colors.surface, child: child),
  ],
);

@widgetbook.UseCase(name: 'Counting down', type: RestPanel)
Widget countingDownRestPanel(BuildContext context) => _panel(
  context,
  RestPanel(
    time: context.knobs.string(label: 'Time', initialValue: '1:12'),
    progress: context.knobs.double.slider(
      label: 'Progress',
      initialValue: 0.6,
      max: 1,
    ),
    next: context.knobs.string(
      label: 'Next',
      initialValue: 'next: set 4 · 82.5 × 8',
    ),
    onAddTime: () {},
    onSkip: () {},
  ),
);

@widgetbook.UseCase(name: 'Rest over', type: RestPanel)
Widget restOverRestPanel(BuildContext context) => _panel(
  context,
  const RestPanel.over(time: '0:00', next: 'next: set 4 · 82.5 × 8'),
);

@widgetbook.UseCase(name: 'No next set', type: RestPanel)
Widget noNextSetRestPanel(BuildContext context) => _panel(
  context,
  RestPanel(
    time: '1:12',
    progress: 0.6,
    next: 'All sets done',
    onAddTime: () {},
    onSkip: () {},
  ),
);
