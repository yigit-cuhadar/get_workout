import 'package:flutter/material.dart';
import 'package:get_workout/features/workout/presentation/widgets/workout_bar.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _bottom(Widget child) =>
    Column(mainAxisAlignment: MainAxisAlignment.end, children: [child]);

@widgetbook.UseCase(name: 'Rest', type: WorkoutBar)
Widget restWorkoutBar(BuildContext context) => _bottom(
  WorkoutBar(
    name: context.knobs.string(label: 'Name', initialValue: 'Push'),
    detail: context.knobs.string(label: 'Detail', initialValue: 'Rest 1:12'),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Workout mode', type: WorkoutBar)
Widget workoutModeWorkoutBar(BuildContext context) => _bottom(
  WorkoutBar(
    name: context.knobs.string(label: 'Name', initialValue: 'Push'),
    detail: context.knobs.string(label: 'Elapsed', initialValue: '24:16'),
    onTap: () {},
  ),
);
