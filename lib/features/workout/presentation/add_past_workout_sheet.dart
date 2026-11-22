import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../domain/workout_editing.dart';
import 'past_workout_pickers.dart';
import 'workout_edit_cubit.dart';
import 'workout_text.dart';

/// Asks what a past workout starts from (date, start time, duration and,
/// with an active program, one of its days to fill the exercises from) and
/// returns it on Continue; null when the sheet is closed.
Future<PastWorkoutPlan?> askPastWorkout(BuildContext context) =>
    showForgeBottomSheet<PastWorkoutPlan>(
      context: context,
      builder: (_) => const _PastWorkoutSheet(),
    );

class _PastWorkoutSheet extends StatefulWidget {
  const _PastWorkoutSheet();

  @override
  State<_PastWorkoutSheet> createState() => _PastWorkoutSheetState();
}

class _PastWorkoutSheetState extends State<_PastWorkoutSheet> {
  late final PastWorkoutPlan _default = WorkoutEditCubit.defaultPlan(
    '',
    DateTime.now(),
    '',
  );
  late DateTime _start = _default.start;
  late Duration _duration = _default.duration;
  int? _dayIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final program = context.select(
      (ProgramListCubit cubit) => cubit.state.activeProgram,
    );
    final dayIndex = program != null && (_dayIndex ?? 0) < program.days.length
        ? _dayIndex
        : null;
    return ForgeBottomSheet(
      title: l10n.pastAddTitle,
      action: ForgeButton(
        label: l10n.pastContinue,
        size: ForgeButtonSize.large,
        onPressed: () => Navigator.pop<PastWorkoutPlan>(context, (
          name: program != null && dayIndex != null
              ? l10n.dayName(program.days[dayIndex], dayIndex)
              : l10n.workoutFreeName,
          start: _start,
          duration: _duration,
          program: dayIndex == null ? null : program,
          dayIndex: dayIndex,
          language: Localizations.localeOf(context).languageCode,
        )),
      ),
      child: ListRowCard(
        children: [
          ListRow(
            title: l10n.historyDate,
            value: DateFormat.MMMEd(l10n.localeName).format(_start),
            end: ListRowEnd.chevron,
            onTap: _pickDate,
          ),
          ListRow(
            title: l10n.historyStartTime,
            value: MaterialLocalizations.of(context)
                .formatTimeOfDay(TimeOfDay.fromDateTime(_start)),
            end: ListRowEnd.chevron,
            onTap: () => showForgeTimeWheel(
              context: context,
              initial: TimeOfDay.fromDateTime(_start),
              onChanged: (time) => setState(
                () => _start = DateTime(
                  _start.year,
                  _start.month,
                  _start.day,
                  time.hour,
                  time.minute,
                ),
              ),
            ),
          ),
          ListRow(
            title: l10n.workoutDuration,
            value: l10n.durationMinutes(_duration),
            end: ListRowEnd.chevron,
            onTap: () => pickWorkoutDuration(
              context,
              _duration,
              (duration) => setState(() => _duration = duration),
            ),
          ),
          if (program != null)
            ListRow(
              title: l10n.pastProgramDay,
              detail: l10n.pastProgramDayDetail,
              value: dayIndex == null
                  ? l10n.pastProgramDayNone
                  : l10n.dayName(program.days[dayIndex], dayIndex),
              end: ListRowEnd.chevron,
              onTap: () => _pickDay(program, dayIndex),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _start.isAfter(now) ? now : _start,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    setState(
      () => _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      ),
    );
  }

  /// "None" and the program's days, the current one picked.
  Future<void> _pickDay(Program program, int? current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showForgeBottomSheet<int>(
      context: context,
      builder: (context) => ForgeBottomSheet(
        title: l10n.pastProgramDay,
        child: ChoiceGrid.list(
          options: [
            ChoiceOption(label: l10n.pastProgramDayNone),
            for (final (i, day) in program.days.indexed)
              ChoiceOption(label: l10n.dayName(day, i)),
          ],
          selected: current == null ? 0 : current + 1,
          onSelected: (index) => Navigator.pop(context, index),
          form: ChoiceListForm.inline,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _dayIndex = picked == 0 ? null : picked - 1);
  }
}
