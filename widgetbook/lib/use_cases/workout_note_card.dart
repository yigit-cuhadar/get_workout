import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/workout_editor_view.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Empty and with a note', type: WorkoutNoteCard)
Widget workoutNoteCard(BuildContext context) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(
    spacing: 10,
    children: [
      WorkoutNoteCard(note: null, onSaved: (_) {}),
      WorkoutNoteCard(
        note: context.knobs.string(
          label: 'Note',
          initialValue: 'Left shoulder a bit tight.',
        ),
        onSaved: (_) {},
      ),
    ],
  ),
);
