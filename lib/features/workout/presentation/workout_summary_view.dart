import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/max_length_formatter.dart';
import '../../../core/text_length.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../core/widgets/muscle_heat.dart';
import '../../../core/widgets/records.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/body_model_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../strength/presentation/strength_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../volume/presentation/volume_text.dart';
import '../domain/exercise_stats.dart';
import 'active_workout_cubit.dart';
import 'workout_text.dart';

/// The finished workout's summary: the featured block with its four
/// figures and their change since the program day's last workout, the
/// records, the muscles worked, and Done over Save as program (a free
/// workout) or Save changes to the day (a program day done differently).
/// Back does what Done does.
class WorkoutSummaryView extends StatefulWidget {
  const WorkoutSummaryView(this.state, {super.key});

  final ActiveWorkoutState state;

  /// How many of the busiest muscles the line names.
  static const shownMuscles = 3;

  @override
  State<WorkoutSummaryView> createState() => _WorkoutSummaryViewState();
}

class _WorkoutSummaryViewState extends State<WorkoutSummaryView> {
  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final cubit = context.read<ActiveWorkoutCubit>();
    final state = widget.state;
    final workout = state.workout!;
    final summary = state.summary!;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final programs = context.select(
      (ProgramListCubit cubit) => cubit.state.programs,
    );
    final model = switch (context.watch<BodyModelCubit>().state) {
      BodyModelReady(:final model) => model,
      _ => null,
    };
    final day = l10n.workoutShortName(workout, programs);
    final program = programs
        .where((p) => p.id == workout.programId)
        .firstOrNull;
    final date = DateFormat.MMMEd(l10n.localeName);
    final previous = summary.previous;
    final compare = [
      ?program?.name,
      if (summary.programWeek case final week?) l10n.summaryWeek(week),
      if (previous != null) l10n.summaryVs(date.format(previous.startedAt)),
    ];
    final busiest = summary.muscleSets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final numbers = NumberFormat.decimalPattern(l10n.localeName);
    final worked = [
      for (final (i, MapEntry(key: muscle, value: sets))
          in busiest.take(WorkoutSummaryView.shownMuscles).indexed)
        l10n.summaryWorkedMuscle(
          l10n.muscleName(muscle),
          i == 0 ? l10n.setsText(sets) : numbers.format(sets),
        ),
    ].join(' · ');
    final canSaveAsProgram =
        !workout.isFromProgram && state.savedProgramId == null;
    final canUpdateDay =
        workout.isFromProgram &&
        program != null &&
        state.dayChanges != null &&
        !state.dayUpdated;
    final secondary = canSaveAsProgram
        ? ForgeButton(
            label: l10n.workoutSaveAsProgram,
            onPressed: state.savingProgram
                ? null
                : () => _saveAsProgram(context, day),
            loading: state.savingProgram,
            variant: ForgeButtonVariant.secondary,
            size: ForgeButtonSize.large,
          )
        : canUpdateDay
        ? ForgeButton(
            label: l10n.summarySaveChanges(day),
            onPressed: state.updatingDay
                ? null
                : () => _updateDay(context, day),
            loading: state.updatingDay,
            variant: ForgeButtonVariant.secondary,
            size: ForgeButtonSize.large,
          )
        : null;
    final done = ForgeButton(
      label: l10n.libraryDone,
      onPressed: cubit.summaryShown,
      size: ForgeButtonSize.large,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cubit.summaryShown();
      },
      child: Scaffold(
        appBar: ForgeAppBar(title: l10n.summaryTitle),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
          children: [
            FeaturedCard(
              form: FeaturedCardForm.block,
              eyebrow: l10n.summaryDoneOn(date.format(workout.startedAt)),
              title: day,
              note: compare.isEmpty ? null : compare.join(' · '),
              stats: _stats(l10n, summary, unit),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xs, 18, Gap.xs, Gap.sm),
              child: Text(
                l10n.summaryRecords,
                style: text.labelMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.inkMuted,
                ),
              ),
            ),
            if (summary.records.isEmpty)
              RecordList.message(
                message: switch (summary) {
                  WorkoutSummary(firstWorkout: true) =>
                    l10n.summaryFirstRecords,
                  WorkoutSummary(:final closest?) =>
                    '${l10n.summaryNoRecords} '
                        '${l10n.summaryClosest(closest.name, l10n.liftedWeightText(closest.kg, unit))}',
                  _ => l10n.summaryNoRecords,
                },
              )
            else
              RecordList(
                records: [
                  for (final record in summary.records)
                    RecordItem(
                      name: record.name,
                      detail: [
                        for (final kind in record.kinds) l10n.recordName(kind),
                      ].join(' · '),
                      value: l10n.setText(record.set, record.loggingType, unit),
                      gain: _gain(l10n, record, unit),
                    ),
                ],
              ),
            if (summary.programUnknown) ...[
              const SizedBox(height: 10),
              // NoticeBanner has no form without a title and an action yet.
              EmptyView(
                icon: ForgeIcons.info,
                message: l10n.workoutProgramUnknown,
                compact: true,
              ),
            ],
            if (worked.isNotEmpty) ...[
              const SizedBox(height: 10),
              WorkedMuscles(
                model: model,
                sets: summary.muscleSets,
                title: l10n.summaryWorkedToday,
                line: worked,
              ),
            ],
          ],
        ),
        bottomNavigationBar: secondary == null
            ? ForgeBottomActionBar(primary: done)
            : ForgeBottomActionBar.stacked(primary: done, secondary: secondary),
      ),
    );
  }

  /// Duration, volume, sets and records; the first three with their
  /// change since [WorkoutSummary.previous]: more volume or sets a gain,
  /// less a drop, a duration neither.
  List<FeaturedStat> _stats(
    AppLocalizations l10n,
    WorkoutSummary summary,
    WeightUnit unit,
  ) {
    final previous = summary.previous;
    String? change(num now, num before, String Function(num) format) {
      if (now == before) return l10n.summaryChangeSame;
      final text = format((now - before).abs());
      return now > before
          ? l10n.summaryChangeUp(text)
          : l10n.summaryChangeDown(text);
    }

    FeaturedChangeTone tone(num now, num before) => now > before
        ? FeaturedChangeTone.gain
        : now < before
        ? FeaturedChangeTone.drop
        : FeaturedChangeTone.neutral;
    final minutes = summary.duration.inMinutes;
    final numbers = NumberFormat.decimalPattern(l10n.localeName);
    final percent = previous == null || previous.volumeKg == 0
        ? null
        : (summary.volumeKg / previous.volumeKg * 100).round() - 100;
    return [
      FeaturedStat(
        l10n.workoutDuration,
        l10n.durationMinutes(summary.duration),
        change: previous == null
            ? null
            : change(
                minutes,
                previous.duration.inMinutes,
                (m) => l10n.durationMinutes(Duration(minutes: m.toInt())),
              ),
      ),
      FeaturedStat(
        l10n.workoutVolume,
        l10n.weightText(summary.volumeKg, unit),
        change: percent == null
            ? null
            : change(
                percent,
                0,
                (value) => l10n.summaryPercent(numbers.format(value)),
              ),
        tone: percent == null ? FeaturedChangeTone.neutral : tone(percent, 0),
      ),
      FeaturedStat(
        l10n.workoutSets,
        '${summary.setCount}',
        change: previous == null
            ? null
            : change(summary.setCount, previous.setCount, numbers.format),
        tone: previous == null
            ? FeaturedChangeTone.neutral
            : tone(summary.setCount, previous.setCount),
      ),
      FeaturedStat(l10n.summaryRecords, '${summary.records.length}'),
    ];
  }

  /// What [record]'s first beaten record gained: "+2.5 kg", "+2 reps",
  /// "+5 s".
  String _gain(AppLocalizations l10n, SummaryRecord record, WeightUnit unit) {
    final amount = record.gain.amount;
    return switch (record.gain.kind) {
      RecordKind.heaviestWeight => l10n.summaryChangeUp(
        l10n.liftedWeightText(amount, unit),
      ),
      RecordKind.bestE1rm => l10n.summaryChangeUp(
        l10n.estimatedWeightText(amount, unit),
      ),
      RecordKind.bestSetVolume => l10n.summaryChangeUp(
        l10n.weightText(amount, unit),
      ),
      RecordKind.mostReps => l10n.summaryGainReps(amount.round()),
      RecordKind.longestDuration => l10n.summaryGainSeconds(amount.round()),
    };
  }

  Future<void> _saveAsProgram(BuildContext context, String name) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final controller = TextEditingController(
      text: cutToLength(name, ProgramLimits.maxNameLength),
    );
    final saved = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.workoutSaveAsProgram,
        message: l10n.summarySaveAsProgramBody,
        field: ForgeTextField(
          label: l10n.workoutSaveAsProgramName,
          controller: controller,
          inputFormatters: [maxLengthFormatter(ProgramLimits.maxNameLength)],
        ),
        action: ForgeButton(
          label: l10n.programSave,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          onPressed: () => Navigator.pop(context, false),
          variant: ForgeButtonVariant.secondary,
        ),
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (saved == true && text.trim().isNotEmpty) {
      await cubit.saveAsProgram(text);
    }
  }

  Future<void> _updateDay(BuildContext context, String day) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final update = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.summaryUpdateDayTitle(day),
        message: l10n.summaryUpdateDayBody(day),
        action: ForgeButton(
          label: l10n.summaryUpdateDay,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          onPressed: () => Navigator.pop(context, false),
          variant: ForgeButtonVariant.secondary,
        ),
      ),
    );
    if (update == true) await cubit.updateProgramDay();
  }
}
