import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/text_length.dart';
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

/// Asks [title] with [body] in a [ForgeDialog]; true when the user picks
/// [confirm], a danger action when it is [destructive].
Future<bool> confirmChoice(
  BuildContext context, {
  required String title,
  required String body,
  required String cancel,
  required String confirm,
  bool destructive = false,
}) async {
  final confirmed = await showForgeDialog<bool>(
    context: context,
    builder: (context) => ForgeDialog(
      title: title,
      message: body,
      action: ForgeButton(
        label: confirm,
        onPressed: () => Navigator.pop(context, true),
        variant: destructive
            ? ForgeButtonVariant.danger
            : ForgeButtonVariant.primary,
      ),
      cancel: ForgeButton(
        label: cancel,
        onPressed: () => Navigator.pop(context, false),
        variant: ForgeButtonVariant.secondary,
      ),
    ),
  );
  return confirmed == true;
}

/// A note as a multi-line [ForgeTextField] of at most [maxLength]
/// characters that applies every change at once.
class NoteField extends StatefulWidget {
  const NoteField({
    super.key,
    required this.initial,
    required this.label,
    required this.hint,
    required this.maxLength,
    required this.onChanged,
  });

  final String? initial;
  final String label;
  final String hint;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  State<NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<NoteField> {
  late final _controller = TextEditingController(text: widget.initial ?? '');
  late String _last = _controller.text;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() {
    final text = _controller.text;
    // The field counts characters; stored notes are capped in UTF-16 code
    // units, which emoji take two or more of.
    if (text.length > widget.maxLength) {
      _controller.text = cutToLength(text, widget.maxLength);
      return;
    }
    if (text == _last) return;
    _last = text;
    widget.onChanged(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ForgeTextField(
    label: widget.label,
    hint: widget.hint,
    controller: _controller,
    multiline: true,
    maxLength: widget.maxLength,
  );
}

/// The workout's [note] as a plain card titled "Workout note": "Add" when
/// there is none, else the note under the title and "Edit"; either opens
/// the note sheet (the field and Save), whose text goes to [onSaved].
class WorkoutNoteCard extends StatelessWidget {
  const WorkoutNoteCard({super.key, required this.note, required this.onSaved});

  final String? note;
  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = this.note;
    return SectionCard.plain(
      title: l10n.workoutNote,
      actionLabel: note == null ? l10n.detailAdd : l10n.historyEdit,
      onAction: () => _edit(context),
      child: note == null
          ? null
          : Text(note, style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    var text = note ?? '';
    final saved = await showForgeBottomSheet<bool>(
      context: context,
      builder: (context) => ForgeBottomSheet(
        title: l10n.workoutNote,
        action: ForgeButton(
          label: l10n.programSave,
          onPressed: () => Navigator.pop(context, true),
          size: ForgeButtonSize.large,
        ),
        child: NoteField(
          initial: note,
          label: l10n.workoutNote,
          hint: l10n.workoutNoteHint,
          maxLength: WorkoutLimits.maxNoteLength,
          onChanged: (changed) => text = changed,
        ),
      ),
    );
    if (saved == true) onSaved(text);
  }
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
              hint: l10n.addSetHint(type),
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
