import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../generator/presentation/generator_entry.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import 'premium_prompt.dart';
import 'program_detail_cubit.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';
import 'program_volume_section.dart';
import 'stop_program_dialog.dart';
import 'weekday_dialog.dart';

/// The Programs tab's first page, the plan: the active program in a header
/// band with this week's days, its weekly sets, then the ways into the
/// ready-made programs, the generator and the builder, then the other
/// programs. A program day starts, and a missed one is answered, on Today.
class ProgramsPage extends StatelessWidget {
  const ProgramsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramListCubit>(),
    child: Scaffold(
      appBar: ForgeAppBar(title: AppLocalizations.of(context).tabPrograms),
      body: _ProgramsView(premium: sl<PremiumPrompt>()),
    ),
  );
}

class _ProgramsView extends StatefulWidget {
  const _ProgramsView({required this.premium});

  final PremiumPrompt premium;

  @override
  State<_ProgramsView> createState() => _ProgramsViewState();
}

class _ProgramsViewState extends State<_ProgramsView> {
  late final ProgramListCubit _cubit = context.read<ProgramListCubit>();
  late final AppLifecycleListener _lifecycle;

  /// The plan's today moves on while the page is away or the app sleeps,
  /// without a new snapshot to recompute it.
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _cubit.refreshNow);
    _cubit.refreshNow();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A refused write is told by the shell's ProgramWritesNotice, a failed
    // missed-day choice by its prompt.
    return BlocBuilder<ProgramListCubit, ProgramListState>(
      builder: (context, state) => switch (state.status) {
        ProgramListStatus.loading => const _Loading(),
        ProgramListStatus.failure => ErrorView(
          title: l10n.programsLoadFailedTitle,
          message: l10n.loadFailedDetail,
          retryLabel: l10n.retry,
          onRetry: _cubit.retry,
        ),
        ProgramListStatus.ready => _Programs(state, premium: widget.premium),
      },
    );
  }
}

/// The page's shape while it loads: the band's skeleton and two cards'.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.all(Gap.md),
    child: LoadingView(),
  );
}

class _Programs extends StatelessWidget {
  const _Programs(this.state, {required this.premium});

  final ProgramListState state;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = state.activeProgram;
    final others = state.otherPrograms;
    final access = active == null ? null : state.access(active);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        if (active == null)
          FeaturedCard(
            form: FeaturedCardForm.prompt,
            eyebrow: l10n.programsStartEyebrow,
            title: l10n.programsStartTitle,
            note: l10n.programsStartDetail,
            action: FeaturedAction(
              l10n.programsSeeCatalogue,
              () => context.go(Routes.catalogue),
            ),
          )
        else ...[
          BlocProvider(
            key: ValueKey(active.id),
            create: (_) => sl<ProgramDetailCubit>(param1: active.id),
            child: _ActiveProgram(state, active, premium: premium),
          ),
          // Kept, not stopped: it carries on once premium is back.
          if (access == ProgramAccess.locked) ...[
            const SizedBox(height: Gap.sm),
            NoticeBanner(
              icon: ForgeIcons.lock,
              title: l10n.programPremiumEndedTitle,
              message: l10n.programPremiumEndedBody(active.name),
              action: ForgeButton(
                label: l10n.programSeePremium,
                variant: ForgeButtonVariant.secondary,
                onPressed: () => premium.show(context),
              ),
            ),
          ],
          if (!state.finished && access != ProgramAccess.waiting) ...[
            const SizedBox(height: Gap.sm),
            ProgramVolumeSection(
              program: active,
              onOpen: () => context.go(Routes.programVolume(active.id!)),
            ),
          ],
        ],
        const SizedBox(height: Gap.sm),
        ListRowCard(
          children: [
            ListRow(
              title: l10n.catalogueTitle,
              detail: l10n.programsCatalogueInfo,
              end: ListRowEnd.chevron,
              onTap: () => context.go(Routes.catalogue),
            ),
            const GeneratorEntry(),
            ListRow(
              title: l10n.programNew,
              detail: l10n.programNewInfo,
              end: ListRowEnd.chevron,
              onTap: () => context.go(Routes.programNew),
            ),
          ],
        ),
        if (state.programs.isEmpty) ...[
          const SizedBox(height: Gap.sm),
          // The prompt above already leads to the catalogue.
          EmptyView(
            title: l10n.programsEmptyTitle,
            message: l10n.programsEmptyDetail,
            card: true,
            compact: true,
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          SectionLabel(active == null ? l10n.programsMine : l10n.programsOther),
          ListRowCard(
            children: [
              for (final program in others)
                _ProgramRow(
                  program,
                  locked: state.access(program) == ProgramAccess.locked,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The active program's band: where it stands and this week's days, or
/// once it finished its result and the ways on; its options in ⋯. No
/// Start: Today's workout card starts the day.
class _ActiveProgram extends StatelessWidget {
  const _ActiveProgram(this.state, this.program, {required this.premium});

  final ProgramListState state;
  final Program program;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final access = state.access(program);
    final weeks = program.lengthWeeks;
    final week = state.week;
    final locked = access == ProgramAccess.locked;
    return BlocListener<ProgramDetailCubit, ProgramDetailState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, detail) {
        switch (detail.status) {
          case ProgramDetailStatus.duplicated:
            context.go(Routes.program(detail.copyId!, created: true));
          case ProgramDetailStatus.failed:
            showForgeSnackbar(
              context,
              message: detail.failure is NetworkFailure
                  ? l10n.errorNetwork
                  : detail.action == ProgramDetailAction.stop
                  ? l10n.programStopFailed
                  : l10n.programActionFailed,
              error: true,
            );
          default:
        }
      },
      child: FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: state.finished
            ? l10n.programFinishedWeeks(weeks ?? 0)
            : week == null
            ? l10n.programActive
            : weeks == null
            ? l10n.programActiveWeek(week)
            : l10n.programActiveWeekOf(week, weeks),
        title: program.name,
        locked: locked,
        menu: _ProgramMenuButton(state, program, premium: premium),
        progress: !state.finished && weeks != null && week != null
            ? week / weeks
            : null,
        note: switch (state.workoutCount) {
          final count? => l10n.programWorkoutCount(count),
          null => null,
        },
        action: state.finished
            ? FeaturedAction(
                l10n.programRunAgain,
                () => _ProgramActions(
                  context,
                  state,
                  program,
                  premium,
                ).runAgain(),
                locked: locked,
              )
            : null,
        moreActions: [
          if (state.finished)
            FeaturedAction(
              l10n.programNew,
              () => context.go(Routes.programNew),
            ),
        ],
        rows: state.finished || locked
            ? const []
            : weekDayRows(context, state, program),
      ),
    );
  }
}

/// The ⋯ of the active program's band.
class _ProgramMenuButton extends StatelessWidget {
  const _ProgramMenuButton(this.state, this.program, {required this.premium});

  final ProgramListState state;
  final Program program;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = context.watch<ProgramDetailCubit>().state.isBusy;
    return Builder(
      builder: (anchor) => ForgeIconButton(
        icon: ForgeIcons.moreHoriz,
        label: l10n.programOptions,
        variant: ForgeIconButtonVariant.onFeatured,
        onPressed: busy
            ? null
            : () => _ProgramActions(anchor, state, program, premium).menu(),
      ),
    );
  }
}

/// What the band's buttons and ⋯ do, through the [ProgramDetailCubit] of
/// the active program above [context].
class _ProgramActions {
  _ProgramActions(this.context, this.state, this.program, this.premium);

  final BuildContext context;
  final ProgramListState state;
  final Program program;
  final PremiumPrompt premium;

  ProgramDetailCubit get _cubit => context.read<ProgramDetailCubit>();

  Future<void> menu() {
    final l10n = AppLocalizations.of(context);
    return showForgeMenu(
      context: context,
      items: [
        ForgeMenuItem(
          label: l10n.programOpen,
          icon: ForgeIcons.description,
          onTap: () => context.go(Routes.program(program.id!)),
        ),
        // A locked copy cannot be rescheduled.
        if (!state.finished && state.access(program) != ProgramAccess.locked)
          ForgeMenuItem(
            label: l10n.programChangeDays,
            icon: ForgeIcons.editCalendar,
            onTap: changeDays,
          ),
        ForgeMenuItem(
          label: l10n.programDuplicate,
          icon: ForgeIcons.contentCopy,
          onTap: () {
            _cubit.duplicate(l10n.programCopyName);
          },
        ),
        ForgeMenuItem(
          label: l10n.programStopConfirm,
          icon: ForgeIcons.stopCircle,
          destructive: true,
          onTap: stop,
        ),
      ],
    );
  }

  Future<void> changeDays() async {
    final active = state.active!;
    final weekdays = await _pickWeekdays(
      active.weekdays,
      AppLocalizations.of(context).programSave,
    );
    if (weekdays != null) await _cubit.changeWeekdays(weekdays);
  }

  Future<void> stop() async {
    final cubit = _cubit;
    if (!await confirmStopProgram(context, program.name)) return;
    await cubit.stop();
  }

  /// Starts the finished program again from today on the weekdays picked;
  /// a locked copy opens the paywall instead.
  Future<void> runAgain() async {
    if (_locked()) return;
    final weekdays = await _pickWeekdays(
      state.active!.weekdays,
      AppLocalizations.of(context).programStart,
    );
    if (weekdays != null) await _cubit.start(weekdays);
  }

  bool _locked() {
    if (state.access(program) != ProgramAccess.locked) return false;
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

/// This week's planned and done days of the active program as date-box
/// rows with their state; a missed day says so, Today asks what to do with
/// it. None starts. While the premium status of a premium copy is unknown,
/// loading rows.
List<Widget> weekDayRows(
  BuildContext context,
  ProgramListState state,
  Program program,
) {
  if (state.access(program) == ProgramAccess.waiting) {
    return [for (var i = 0; i < 3; i++) ListRow.loading(index: i)];
  }
  final l10n = AppLocalizations.of(context);
  final success = ForgeStyle.of(context).colors.success;
  final missed = state.missed;
  bool isNext(PlannedDay day) =>
      day.status == PlannedStatus.planned &&
      day.dayIndex == state.nextDayIndex &&
      day.date == state.nextDate;
  Widget row(PlannedDay day) => ListRow(
    leading: ListRowDateBox(
      weekday: l10n.weekdayShort(day.date.weekday),
      day: '${day.date.day}',
      state: switch (day.status) {
        PlannedStatus.done => DayState.done,
        PlannedStatus.missed => DayState.missed,
        PlannedStatus.planned when day.date == state.today => DayState.today,
        PlannedStatus.planned => DayState.planned,
      },
    ),
    title: day.dayIndex < program.days.length
        ? l10n.dayName(program.days[day.dayIndex], day.dayIndex)
        : l10n.programDayDefault(day.dayIndex + 1),
    detail: switch (day.status) {
      PlannedStatus.done => l10n.programDayDone,
      PlannedStatus.missed => null,
      PlannedStatus.planned when isNext(day) => l10n.programDayNext,
      PlannedStatus.planned => l10n.programDayPlanned,
    },
    error: day.status == PlannedStatus.missed ? l10n.programDayMissed : null,
    trailing: day.status == PlannedStatus.done
        ? ForgeIcon(ForgeIcons.check, size: 16, color: success)
        : null,
  );
  final plan = state.weekPlan;
  return [
    // A day missed in an earlier week waits above this week's.
    if (missed != null && !plan.contains(missed)) row(missed),
    for (final day in plan) row(day),
    if (plan.isEmpty && missed == null) ListRow(title: l10n.programWeekEmpty),
  ];
}

class _ProgramRow extends StatelessWidget {
  const _ProgramRow(this.program, {required this.locked});

  final Program program;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weeks = program.lengthWeeks;
    return ListRow(
      title: program.name,
      detail: [
        l10n.programDayCount(program.days.length),
        if (weeks != null) l10n.programWeekCount(weeks),
      ].join(' · '),
      // A locked copy keeps full colour.
      trailing: locked
          ? ForgeTag(l10n.cataloguePremium, kind: ForgeTagKind.premium)
          : null,
      end: locked ? ListRowEnd.none : ListRowEnd.chevron,
      onTap: () => context.go(Routes.program(program.id!)),
    );
  }
}
