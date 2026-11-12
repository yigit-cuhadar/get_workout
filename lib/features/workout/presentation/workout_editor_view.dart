import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import 'workout_editor.dart';
import 'workout_text.dart';

/// Asks [title] with [body]; true when the user picks [confirm].
Future<bool> confirmChoice(
  BuildContext context, {
  required String title,
  required String? body,
  required String cancel,
  required String confirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// The exercises of the workout [editor] edits by name, reordered by
/// dragging; groups move as one.
class ReorderSheet extends StatelessWidget {
  const ReorderSheet({super.key, required this.editor});

  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<WorkoutEditor<EditedWorkout>, EditedWorkout>(
      bloc: editor,
      buildWhen: (previous, current) =>
          previous.workout?.exercises != current.workout?.exercises,
      builder: (context, state) {
        final exercises = state.workout?.exercises ?? const [];
        return SafeArea(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: exercises.length,
            onReorderItem: editor.moveExercise,
            itemBuilder: (context, index) {
              final exercise = exercises[index];
              return ListTile(
                key: ValueKey(index),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    semanticLabel: l10n.programReorder,
                  ),
                ),
                title: Text(exercise.name),
                trailing: exercise.group == null ? null : Text(exercise.group!),
              );
            },
          ),
        );
      },
    );
  }
}

/// A multi-line note that applies every change at once.
class NoteField extends StatefulWidget {
  const NoteField({
    super.key,
    required this.initial,
    required this.label,
    required this.maxLength,
    required this.onChanged,
  });

  final String? initial;
  final String label;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  State<NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<NoteField> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: null,
    textCapitalization: TextCapitalization.sentences,
    inputFormatters: [maxLengthFormatter(widget.maxLength)],
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}

/// Asks which kind of set to add to exercise [index] of the workout
/// [editor] edits, and adds it; one tap each.
Future<void> addSetOfKind(
  BuildContext context,
  WorkoutEditor<EditedWorkout> editor,
  int index,
) async {
  final l10n = AppLocalizations.of(context);
  final exercise = editor.state.workout?.exercises.elementAtOrNull(index);
  if (exercise == null) return;
  final type = await showModalBottomSheet<SetType>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in SetType.values)
            if (type != SetType.drop || exercise.loggingType.logsReps)
              ListTile(
                title: Text(l10n.setTypeLabel(type)),
                onTap: () => Navigator.pop(context, type),
              ),
        ],
      ),
    ),
  );
  if (type != null) editor.addSet(index, type);
}
