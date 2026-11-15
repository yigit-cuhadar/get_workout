import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import '../domain/program_usecases.dart';
import 'missed_day_prompt.dart';
import 'premium_prompt.dart';
import 'program_day_section.dart';
import 'program_detail_cubit.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';
import 'program_volume_section.dart';
import 'stop_program_dialog.dart';
import 'weekday_dialog.dart';

/// One program: a header band with where it stands and what can be done
/// with it (start, the next day, a missed day, change days, stop, run it
/// again), its weekly sets, then its days, which open to their exercises;
/// Edit, Duplicate and Delete in the app bar's ⋯. Taken from the shared
/// list, so it opens at once from the list and also works from a bare link.
class ProgramDetailPage extends StatefulWidget {
  const ProgramDetailPage({super.key, required this.id, this.created = false});

  final String id;

  /// The program was just stored: the list may not show it yet, so the page
  /// waits for it, for up to [createdWait], before saying it does not exist.
  final bool created;

  static const createdWait = Duration(seconds: 3);

  @override
  State<ProgramDetailPage> createState() => _ProgramDetailPageState();
}

class _ProgramDetailPageState extends State<ProgramDetailPage> {
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.created) {
      _wait = Timer(ProgramDetailPage.createdWait, () => setState(() {}));
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  bool get _waiting => _wait?.isActive ?? false;

  String get id => widget.id;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramListCubit>(),
    child: BlocBuilder<ProgramListCubit, ProgramListState>(
      // Once shown, the page keeps its program; a delete removing it from
      // the list must not swap the page out while it closes.
      buildWhen: (previous, current) =>
          previous.program(id) == null || current.program(id) != null,
      builder: (context, state) {
        final program = state.program(id);
        if (program != null) {
          return BlocProvider(
            create: (_) => sl<ProgramDetailCubit>(param1: id),
            child: _ProgramDetailView(
              program: program,
              list: state,
              premium: sl<PremiumPrompt>(),
            ),
          );
        }
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: const ForgeAppBar(title: ''),
          body: switch (state.status) {
            ProgramListStatus.failure => ErrorView(
              title: l10n.programsLoadFailedTitle,
              message: l10n.loadFailedDetail,
              retryLabel: l10n.retry,
              onRetry: context.read<ProgramListCubit>().retry,
            ),
            ProgramListStatus.ready when !_waiting => EmptyView(
              message: l10n.programNotFound,
            ),
            _ => const SingleChildScrollView(
              padding: EdgeInsets.all(Gap.md),
              child: LoadingView(),
            ),
          },
        );
      },
    ),
  );
}

class _ProgramDetailView extends StatelessWidget {
  const _ProgramDetailView({
    required this.program,
    required this.list,
    required this.premium,
  });

  final Program program;
  final ProgramListState list;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = list.active?.programId == program.id ? list.active : null;
    return BlocConsumer<ProgramDetailCubit, ProgramDetailState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case ProgramDetailStatus.deleted || ProgramDetailStatus.closed:
            context.go(Routes.programs);
          case ProgramDetailStatus.duplicated:
            context.go(Routes.program(state.copyId!, created: true));
          case ProgramDetailStatus.failed:
            showForgeSnackbar(
              context,
              message: state.failure is NetworkFailure
                  ? l10n.errorNetwork
                  : state.action == ProgramDetailAction.stop
                  ? l10n.programStopFailed
                  : l10n.programActionFailed,
              error: true,
            );
          default:
        }
      },
      builder: (context, state) {
        final actions = _DetailActions(context, program, list, premium);
        return Scaffold(
          appBar: ForgeAppBar(
            title: program.name,
            actions: [
              Builder(
                builder: (anchor) => ForgeAppBarAction.icon(
                  icon: ForgeIcons.moreHoriz,
                  label: l10n.programOptions,
                  onPressed: state.isBusy
                      ? null
                      : () => _DetailActions(
                          anchor,
                          program,
                          list,
                          premium,
                        ).menu(isActive: active != null),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              _Band(
                program: program,
                list: list,
                busy: state.isBusy,
                actions: actions,
              ),
              // While the premium status of a premium copy is unknown, the
              // card waits too.
              if (list.access(program) != ProgramAccess.waiting) ...[
                const SizedBox(height: Gap.sm),
                ProgramVolumeSection(
                  program: program,
                  onOpen: () => context.go(Routes.programVolume(program.id!)),
                ),
              ],
              ProgramDaysHeader(l10n.programDays),
              _Days(
                program: program,
                // Where the user is in the program; the start of one not
                // running.
                open: active == null ? 0 : list.nextDayIndex,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The "Days" header over a program's day cards.
class ProgramDaysHeader extends StatelessWidget {
  const ProgramDaysHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.md, Gap.xs, Gap.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: ForgeStyle.of(context).colors.inkMuted,
      ),
    ),
  );
}

/// What the band's buttons and the app bar's ⋯ do, through the
/// [ProgramDetailCubit] above [context].
class _DetailActions {
  _DetailActions(this.context, this.program, this.list, this.premium);

  final BuildContext context;
  final Program program;
  final ProgramListState list;
  final PremiumPrompt premium;

  ProgramDetailCubit get _cubit => context.read<ProgramDetailCubit>();

  Future<void> menu({required bool isActive}) {
    final l10n = AppLocalizations.of(context);
    return showForgeMenu(
      context: context,
      items: [
        ForgeMenuItem(
          label: l10n.programEdit,
          icon: ForgeIcons.edit,
          onTap: () => context.go(Routes.programEdit(program.id!)),
        ),
        ForgeMenuItem(
          label: l10n.programDuplicate,
          icon: ForgeIcons.contentCopy,
          onTap: () {
            _cubit.duplicate(l10n.programCopyName);
          },
        ),
        ForgeMenuItem(
          label: l10n.programDelete,
          icon: ForgeIcons.delete,
          destructive: true,
          onTap: () => delete(isActive: isActive),
        ),
      ],
    );
  }

  /// Starts the program on the weekdays picked, after confirming that it
  /// replaces the active one; a locked one opens the paywall instead.
  Future<void> start() async {
    final l10n = AppLocalizations.of(context);
    final cubit = _cubit;
    if (_locked()) return;
    final current = list.activeProgram;
    if (current != null && current.id != program.id) {
      final replace = await showForgeDialog<bool>(
        context: context,
        builder: (context) => ForgeDialog(
          title: l10n.programReplaceTitle,
          message: l10n.programReplaceBody(current.name),
          action: ForgeButton(
            label: l10n.programReplace,
            onPressed: () => Navigator.pop(context, true),
          ),
          cancel: ForgeButton(
            label: l10n.cancel,
            variant: ForgeButtonVariant.secondary,
            onPressed: () => Navigator.pop(context, false),
          ),
        ),
      );
      if (replace != true || !context.mounted) return;
    }
    final weekdays = await _pickWeekdays(
      list.active?.programId == program.id
          ? list.active!.weekdays
          : ProgramSchedule.suggestedWeekdays(program.days.length),
      l10n.programStart,
    );
    if (weekdays != null) await cubit.start(weekdays);
  }

  Future<void> changeDays() async {
    final cubit = _cubit;
    final weekdays = await _pickWeekdays(
      list.active!.weekdays,
      AppLocalizations.of(context).programSave,
    );
    if (weekdays != null) await cubit.changeWeekdays(weekdays);
  }

  Future<void> stop() async {
    final cubit = _cubit;
    if (!await confirmStopProgram(context, program.name)) return;
    await cubit.stop();
  }

  Future<void> delete({required bool isActive}) async {
    final l10n = AppLocalizations.of(context);
    final cubit = _cubit;
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.programDeleteTitle,
        message: isActive
            ? l10n.programDeleteActiveBody
            : l10n.programDeleteBody,
        action: ForgeButton(
          label: l10n.programDelete,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
    );
    if (confirmed == true) await cubit.delete();
  }

  bool _locked() {
    if (list.access(program) != ProgramAccess.locked) return false;
    premium.show(context);
    return true;
  }

  Future<List<int>?> _pickWeekdays(List<int> current, String confirmLabel) {
    final count = program.days.length;
    return showWeekdayDialog(
      context,
      count: count,
      initial: current.length == count
          ? current
          : ProgramSchedule.suggestedWeekdays(count),
      confirmLabel: confirmLabel,
    );
  }
}

/// Where the program stands, in the FeaturedCard band: not active (Start
/// program), active (its next day and Start, Change days and Stop), a
/// missed day to answer first, finished (Run it again, New program) or a
/// locked premium copy (Start opens the paywall).
class _Band extends StatelessWidget {
  const _Band({
    required this.program,
    required this.list,
    required this.busy,
    required this.actions,
  });

  final Program program;
  final ProgramListState list;
  final bool busy;
  final _DetailActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final access = list.access(program);
    final locked = access == ProgramAccess.locked;
    final waiting = access == ProgramAccess.waiting;
    final active = list.active?.programId == program.id ? list.active : null;
    final weeks = program.lengthWeeks;
    final size = [
      if (weeks != null) l10n.programWeekCount(weeks),
      l10n.programDayCount(program.days.length),
    ];
    VoidCallback? unlessBusy(VoidCallback action) => busy ? null : action;
    final note = !locked
        ? null
        : active == null
        ? l10n.programLockedStart
        : l10n.programLockedActive;

    if (active == null) {
      return FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: size.join(' · '),
        title: l10n.programStateInactive,
        locked: locked,
        note: note,
        action: FeaturedAction(
          l10n.programStart,
          unlessBusy(actions.start),
          locked: locked,
          loading: busy || waiting,
        ),
      );
    }

    final weekdays = l10n.weekdayList(
      active.weekdays,
      context.watchFirstWeekday(),
    );
    if (list.finished) {
      return FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: [...size, weekdays].join(' · '),
        title: l10n.programFinished,
        locked: locked,
        note: note,
        action: FeaturedAction(
          l10n.programRunAgain,
          unlessBusy(actions.start),
          locked: locked,
          loading: busy || waiting,
        ),
        moreActions: [
          FeaturedAction(l10n.programNew, () => context.go(Routes.programNew)),
        ],
      );
    }

    final week = list.week;
    final eyebrow = [
      if (week == null)
        l10n.programStateActive
      else if (weeks == null)
        l10n.programEyebrowWeek(week)
      else
        l10n.programEyebrowWeekOf(week, weeks),
      weekdays,
    ].join(' · ');
    final progress = weeks != null && week != null ? week / weeks : null;
    final mismatch = active.weekdays.length != program.days.length
        ? l10n.programDaysMismatch(program.days.length)
        : null;
    final stop = FeaturedAction(
      l10n.programStop,
      unlessBusy(actions.stop),
      danger: true,
    );
    final footActions = [
      // A locked copy cannot be rescheduled.
      if (!locked)
        FeaturedAction(l10n.programChangeDays, unlessBusy(actions.changeDays)),
      stop,
    ];

    // A locked copy keeps its next day and Start, which opens the paywall.
    final missed = locked ? null : list.missed;
    if (missed != null) {
      final name = _dayName(l10n, missed.dayIndex);
      final resolving = list.resolving || busy;
      VoidCallback? resolve(MissedDayChoice choice) =>
          resolving ? null : () => resolveMissedDay(context, choice);
      return FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: eyebrow,
        title: name,
        alert: mismatch,
        progress: progress,
        line: FeaturedLine.missed(
          l10n.programMissedTitle(name, l10n.planDate(missed.date)),
          status: l10n.programDayMissed,
        ),
        action: FeaturedAction(
          l10n.programMissedToday,
          resolve(MissedDayChoice.doToday),
        ),
        moreActions: [
          FeaturedAction(
            l10n.programMissedMove(l10n.weekdayLong(list.moveDate!.weekday)),
            resolve(MissedDayChoice.moveToNextWeekday),
          ),
          FeaturedAction(l10n.programMissedSkip, resolve(MissedDayChoice.skip)),
        ],
        footActions: footActions,
      );
    }

    final next = list.nextDayIndex;
    final date = list.nextDate;
    final dayName = next == null ? null : _dayName(l10n, next);
    return FeaturedCard(
      form: FeaturedCardForm.band,
      eyebrow: eyebrow,
      title: dayName == null
          ? l10n.programStateActive
          : date == null
          ? l10n.programNextDay(dayName)
          : date == list.today
          ? l10n.programNextToday(dayName)
          : l10n.programNextOn(dayName, l10n.planDate(date)),
      locked: locked,
      note: note,
      alert: mismatch,
      progress: progress,
      action: dayName == null
          ? null
          : FeaturedAction(
              l10n.workoutStartDay(dayName),
              unlessBusy(() => startProgramDay(context, program, next!)),
              locked: locked,
              loading: waiting,
            ),
      footActions: footActions,
    );
  }

  String _dayName(AppLocalizations l10n, int index) =>
      index < program.days.length
      ? l10n.dayName(program.days[index], index)
      : l10n.programDayDefault(index + 1);
}

/// The program's days as cards that open to their exercises. Which are
/// open is this page's own view state: the [open] day at first, again once
/// the days change (an edit may have moved them), and added when [open]
/// moves on, e.g. once the program starts.
class _Days extends StatefulWidget {
  const _Days({required this.program, required this.open});

  final Program program;
  final int? open;

  @override
  State<_Days> createState() => _DaysState();
}

class _DaysState extends State<_Days> {
  late var _open = {?widget.open};

  @override
  void didUpdateWidget(_Days oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.program.days, widget.program.days)) {
      _open = {?widget.open};
    } else if (widget.open case final open? when open != oldWidget.open) {
      _open.add(open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = widget.program;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        for (final (index, day) in program.days.indexed)
          ProgramDayCard(
            day: day,
            index: index,
            open: _open.contains(index),
            onToggle: () => _toggle(index),
          ),
      ],
    );
  }

  void _toggle(int index) => setState(() {
    if (!_open.remove(index)) _open.add(index);
  });
}
