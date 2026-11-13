import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/set_logging.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import '../domain/workout_tips.dart';
import 'workout_editor.dart';
import 'workout_help.dart';
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
/// [editor] edits, each with what it is, and adds it; one tap each. The
/// first time, a tip tells what the kinds are. Needs [SettingsCubit] above.
Future<void> addSetOfKind(
  BuildContext context,
  WorkoutEditor<EditedWorkout> editor,
  int index,
) async {
  final exercise = editor.state.workout?.exercises.elementAtOrNull(index);
  if (exercise == null) return;
  final settings = context.read<SettingsCubit>();
  final type = await showModalBottomSheet<SetType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final seen = context.select(
        (SettingsCubit cubit) =>
            cubit.state.loaded ? cubit.state.settings.seenTips : null,
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text(
                  l10n.workoutAddSet,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                trailing: const WorkoutHelpButton(),
              ),
              if (setTypesTipDue(seen))
                TipBanner(
                  text: l10n.tipSetTypes,
                  onDismiss: () => settings.tipSeen(Tip.setTypes),
                ),
              for (final type in exercise.loggingType.setTypes)
                ListTile(
                  title: Text(l10n.setTypeLabel(type)),
                  subtitle: Text(l10n.setTypeHint(type)),
                  onTap: () => Navigator.pop(context, type),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (type == null) return;
  // Picking a kind is what the tip was for.
  unawaited(settings.tipSeen(Tip.setTypes));
  editor.addSet(index, type);
}
