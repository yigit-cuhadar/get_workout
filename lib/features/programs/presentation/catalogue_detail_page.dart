import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../profile/presentation/profile_questions.dart';
import '../domain/catalogue_program.dart';
import '../domain/program_schedule.dart';
import 'catalogue_detail_cubit.dart';
import 'premium_prompt.dart';
import 'program_catalogue_cubit.dart';
import 'program_day_section.dart';
import 'program_detail_page.dart';
import 'program_text.dart';
import 'program_volume_section.dart';
import 'training_days_sheet.dart';

/// One ready-made program: its name, tags and summary, its facts as rows,
/// its weekly sets and its days, which open in place; Start this program
/// at the bottom (Get Premium to start when it is locked) and Duplicate in
/// ⋯ to edit a copy.
class CatalogueDetailPage extends StatelessWidget {
  const CatalogueDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    // Read here: a provider's create may not depend on inherited widgets.
    final language = Localizations.localeOf(context).languageCode;
    // The catalogue's own route provides the app-wide catalogue only to
    // itself; this page is a route of its own.
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<ProgramCatalogueCubit>()),
        BlocProvider(
          create: (_) => sl<CatalogueDetailCubit>(param1: id, param2: language),
        ),
      ],
      child: _CatalogueDetailView(sl<PremiumPrompt>()),
    );
  }
}

class _CatalogueDetailView extends StatelessWidget {
  const _CatalogueDetailView(this.premium);

  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CatalogueDetailCubit>();
    return BlocConsumer<CatalogueDetailCubit, CatalogueDetailState>(
      listenWhen: (previous, current) =>
          previous.copyStatus != current.copyStatus,
      listener: (context, state) {
        switch (state.copyStatus) {
          case CopyStatus.copied:
            final id = state.copyId!;
            final intent = state.copyIntent;
            cubit.copyHandled();
            context.go(
              intent == CopyIntent.edit
                  ? Routes.programEdit(id)
                  : Routes.program(id, created: true),
            );
          case CopyStatus.failed:
            cubit.copyHandled();
            showForgeSnackbar(
              context,
              message: switch (state.copyFailure) {
                NetworkFailure() => l10n.errorNetwork,
                ValidationFailure() => l10n.catalogueCopyInvalid,
                _ => l10n.catalogueCopyFailed,
              },
              error: true,
            );
          case CopyStatus.startFailed:
            cubit.copyHandled();
            showForgeSnackbar(
              context,
              message: l10n.catalogueStartFailed,
              error: true,
            );
          case CopyStatus.idle || CopyStatus.copying:
        }
      },
      builder: (context, state) {
        final program = state.program;
        final ready = state.status == CatalogueDetailStatus.ready;
        final body = program != null && state.status.showsProgram
            ? null
            : switch (state.status) {
                CatalogueDetailStatus.notFound => EmptyView(
                  message: l10n.catalogueNotFound,
                ),
                CatalogueDetailStatus.offline => ErrorView(
                  title: l10n.catalogueDetailOfflineTitle,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: cubit.retry,
                ),
                CatalogueDetailStatus.failure => ErrorView(
                  title: l10n.catalogueLoadFailedTitle,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: cubit.retry,
                ),
                _ => const SingleChildScrollView(
                  padding: EdgeInsets.all(Gap.md),
                  child: LoadingView(),
                ),
              };
        final canCopy = ready && state.useStatus == UseStatus.ready;
        return Scaffold(
          appBar: ForgeAppBar(
            title: '',
            actions: [
              // A locked program's days cannot be copied.
              if (canCopy)
                Builder(
                  builder: (anchor) => ForgeAppBarAction.icon(
                    icon: ForgeIcons.moreHoriz,
                    label: l10n.programOptions,
                    onPressed: state.copyStatus == CopyStatus.copying
                        ? null
                        : () => showForgeMenu(
                            context: anchor,
                            items: [
                              ForgeMenuItem(
                                label: l10n.programDuplicate,
                                icon: ForgeIcons.contentCopy,
                                onTap: () => cubit.copy(CopyIntent.edit),
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
          body: body ?? _Program(program: program!, state: state),
          bottomNavigationBar: body == null
              ? _Action(state: state, premium: premium)
              : null,
        );
      },
    );
  }
}

extension on CatalogueDetailStatus {
  /// The states that show the program's page rather than one message.
  bool get showsProgram => switch (this) {
    CatalogueDetailStatus.ready ||
    CatalogueDetailStatus.locked ||
    CatalogueDetailStatus.unlocking => true,
    _ => false,
  };
}

class _Program extends StatefulWidget {
  const _Program({required this.program, required this.state});

  final CatalogueProgram program;
  final CatalogueDetailState state;

  @override
  State<_Program> createState() => _ProgramState();
}

class _ProgramState extends State<_Program> {
  /// The days open; the first at first.
  final _open = {0};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final cubit = context.read<CatalogueDetailCubit>();
    final program = widget.program;
    final state = widget.state;
    final language = Localizations.localeOf(context).languageCode;
    final copy = program.text(language);
    final catalogue = context.watch<ProgramCatalogueCubit>().state;
    final locked = state.status == CatalogueDetailStatus.locked;
    final ready = state.status == CatalogueDetailStatus.ready;
    final length = l10n.catalogueLengthText(program);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Semantics(
                header: true,
                child: Text(copy.name, style: text.headlineMedium),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (catalogue.profile.suits(program))
                    ForgeTag(l10n.programCardFits, kind: ForgeTagKind.record),
                  if (locked)
                    ForgeTag(l10n.cataloguePremium, kind: ForgeTagKind.premium),
                  ForgeTag(l10n.goalName(program.goal)),
                ],
              ),
              Text(
                copy.summary,
                style: text.bodyMedium!.copyWith(color: style.colors.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        ListRowCard(
          children: [
            ListRow(
              title: l10n.programDays,
              value: l10n.catalogueDaysAWeek(program.daysPerWeek),
            ),
            ListRow(
              title: l10n.catalogueFilterLevel,
              value: l10n.levelName(program.level),
            ),
            if (length != null)
              ListRow(title: l10n.catalogueLength, value: length),
            ListRow(
              title: l10n.catalogueFilterGoal,
              value: l10n.goalName(program.goal),
            ),
            ListRow(
              title: l10n.catalogueFilterEquipment,
              value: l10n.presetName(program.equipmentProfile),
            ),
          ],
        ),
        if (state.status == CatalogueDetailStatus.unlocking) ...[
          const SizedBox(height: Gap.sm),
          NoticeBanner(
            icon: ForgeIcons.lock,
            title: l10n.catalogueUnlockingTitle,
            message: l10n.catalogueUnlocking,
            action: ForgeButton(
              label: l10n.retry,
              variant: ForgeButtonVariant.secondary,
              onPressed: cubit.retry,
            ),
          ),
        ],
        if (ready) ...[
          const SizedBox(height: Gap.sm),
          ProgramVolumeSection(
            program: program.copy(state.days, language),
            onOpen: () => context.go(Routes.catalogueVolume(program.id)),
          ),
        ],
        if (ready || (locked && program.dayList != null))
          ProgramDaysHeader(l10n.programDays),
        if (ready)
          for (final (index, day) in state.days.indexed) ...[
            if (index > 0) const SizedBox(height: Gap.sm),
            ProgramDayCard(
              day: day,
              index: index,
              open: _open.contains(index),
              estimate: false,
              onToggle: () => setState(() {
                if (!_open.remove(index)) _open.add(index);
              }),
              onExerciseTap: (exerciseId) => context.push(
                Routes.catalogueExercise(program.id, exerciseId),
              ),
            ),
          ]
        else if (locked)
          // Its days cannot be read without Premium: their names and
          // counts only, which open nothing.
          for (final (index, day) in (program.dayList ?? []).indexed) ...[
            if (index > 0) const SizedBox(height: Gap.sm),
            ListRowCard(
              children: [
                ListRow(
                  title: l10n.dayTitle(index, day.name),
                  detail: l10n.programExerciseCount(day.exercises),
                ),
              ],
            ),
          ],
        if (ready && state.useStatus == UseStatus.exercisesMissing)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.md, Gap.xs, 0),
            child: Text(
              l10n.catalogueExercisesMissing,
              style: text.bodyMedium!.copyWith(color: style.colors.inkMuted),
            ),
          ),
        if (ready && state.useStatus == UseStatus.exercisesFailed)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Row(
              spacing: Gap.sm,
              children: [
                Expanded(
                  child: Text(
                    l10n.catalogueExercisesFailed,
                    style: text.bodySmall!.copyWith(color: style.colors.danger),
                  ),
                ),
                ForgeButton(
                  label: l10n.retry,
                  variant: ForgeButtonVariant.outline,
                  onPressed: cubit.retryExercises,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The bar at the bottom: Start this program, or Get Premium to start for
/// a locked program; none while it unlocks.
class _Action extends StatelessWidget {
  const _Action({required this.state, required this.premium});

  final CatalogueDetailState state;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (state.status) {
      CatalogueDetailStatus.locked => ForgeBottomActionBar(
        primary: ForgeButton(
          label: l10n.catalogueGetPremiumToStart,
          onPressed: () => premium.show(context),
        ),
      ),
      CatalogueDetailStatus.ready => ForgeBottomActionBar(
        primary: ForgeButton(
          label: l10n.catalogueStart,
          loading:
              state.useStatus == UseStatus.waiting ||
              state.copyStatus == CopyStatus.copying,
          onPressed: state.useStatus == UseStatus.ready
              ? () => _start(context)
              : null,
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  /// Offers the user's copy if they have one; then, after confirming that
  /// it replaces the active program, asks for the weekdays. Only once they
  /// are picked is the copy made and started.
  Future<void> _start(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CatalogueDetailCubit>();
    if (cubit.existingCopyId case final copyId?) {
      final another = await showForgeDialog<bool>(
        context: context,
        builder: (context) => ForgeDialog(
          title: l10n.catalogueAlreadyTitle,
          message: l10n.catalogueAlreadyBody,
          action: ForgeButton(
            label: l10n.catalogueOpenCopy,
            onPressed: () => Navigator.pop(context, false),
          ),
          cancel: ForgeButton(
            label: l10n.catalogueCopyAgain,
            variant: ForgeButtonVariant.secondary,
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (another == null || !context.mounted) return;
      if (!another) return context.go(Routes.program(copyId));
    }
    if (cubit.activeProgramName case final current?) {
      final replace = await showForgeDialog<bool>(
        context: context,
        builder: (context) => ForgeDialog(
          title: l10n.programReplaceTitle,
          message: l10n.programReplaceBody(current),
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
    final schedule = await showTrainingDays(
      context,
      dayNames: [
        for (final (index, day) in state.days.indexed) l10n.dayName(day, index),
      ],
      initial: ProgramSchedule.suggestedSchedule(state.days.length),
      confirmLabel: l10n.programStart,
    );
    if (schedule == null) return;
    await cubit.copy(CopyIntent.start, schedule: schedule);
  }
}

extension on AppLocalizations {
  /// "8 weeks · 45–60 min", "8 weeks · ~55 min"; null with neither.
  String? catalogueLengthText(CatalogueProgram program) {
    final weeks = program.lengthWeeks;
    final minutes = program.minutes;
    final parts = [
      if (weeks != null) programWeekCount(weeks),
      if (minutes != null)
        minutes.min == minutes.max
            ? programEstimate(minutes.min)
            : catalogueMinutesSpan(minutes.min, minutes.max),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
