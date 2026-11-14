import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/set_logging.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart' as editing;
import '../domain/workout_tips.dart';
import 'widgets/set_type_menu.dart';
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
/// [editor] edits in an [AddSetSheet], each with the bubble it would get
/// and what it is, and adds it; one tap each. The first time, a tip tells
/// what the kinds are. Needs [SettingsCubit] above.
Future<void> addSetOfKind(
  BuildContext context,
  WorkoutEditor<EditedWorkout> editor,
  int index,
) async {
  final exercise = editor.state.workout?.exercises.elementAtOrNull(index);
  if (exercise == null) return;
  final settings = context.read<SettingsCubit>();
  final type = await showForgeBottomSheet<SetType>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final seen = context.select(
        (SettingsCubit cubit) =>
            cubit.state.loaded ? cubit.state.settings.seenTips : null,
      );
      return AddSetSheet(
        title: l10n.workoutAddSet,
        tip: setTypesTipDue(seen)
            ? TipBanner(
                message: l10n.tipSetTypes,
                dismissLabel: l10n.tipDismiss,
                onDismiss: () => settings.tipSeen(Tip.setTypes),
              )
            : null,
        options: [
          for (final type in exercise.loggingType.setTypes)
            AddSetOption(
              label: l10n.setTypeLabel(type),
              hint: l10n.setTypeHint(type),
              bubble: _newSetLabel(l10n, exercise, type),
              warmup: type == SetType.warmup,
              onTap: () => Navigator.pop(context, type),
            ),
        ],
      );
    },
  );
  if (type == null) return;
  // Picking a kind is what the tip was for.
  unawaited(settings.tipSeen(Tip.setTypes));
  editor.addSet(index, type);
}

/// The label a new set of [type] would get in [exercise].
String _newSetLabel(
  AppLocalizations l10n,
  WorkoutExercise exercise,
  SetType type,
) {
  final at = editing.newSetPosition(exercise, type);
  final added = exercise.copyWith(
    sets: [...exercise.sets]..insert(at, WorkoutSet(type: type)),
  );
  return l10n.setLabel(added, at);
}
