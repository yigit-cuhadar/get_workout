import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/first_weekday.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/muscle_meshes.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/body_model_cubit.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/weekly_volume.dart';
import 'volume_charts.dart';
import 'volume_cubit.dart';
import 'volume_text.dart';

/// A week's sets per muscle on the body model and as bars against the
/// reference band; a muscle opens where its sets came from and, with
/// Premium, its 12-week trend.
class VolumePage extends StatelessWidget {
  const VolumePage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = MaterialLocalizations.of(context).firstWeekday;
    return BlocProvider(
      key: ValueKey(firstWeekday),
      create: (_) => sl<VolumeCubit>(param1: firstWeekday),
      child: const _VolumeView(),
    );
  }
}

class _VolumeView extends StatelessWidget {
  const _VolumeView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<VolumeCubit>();
    final state = context.watch<VolumeCubit>().state;
    final shown = state.shown;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.volumeTitle)),
      body: Column(
        children: [
          _WeekSelector(state),
          Expanded(
            // While another week loads the one before stays, so the model
            // keeps its camera and nothing flashes.
            child: switch (state.status) {
              VolumeStatus.failure => ErrorView(
                message: l10n.volumeLoadFailed,
                retryLabel: l10n.retry,
                onRetry: cubit.retry,
              ),
              _ when shown == null => const LoadingView(),
              _ => _Week(state, shown),
            },
          ),
        ],
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector(this.state);
  final VolumeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<VolumeCubit>();
    return Row(
      children: [
        IconButton(
          tooltip: l10n.volumePreviousWeek,
          onPressed: cubit.previousWeek,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            _weekLabel(context, state),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: l10n.volumeNextWeek,
          onPressed: state.hasNext ? cubit.nextWeek : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// "This week", or the week's first and last day.
String _weekLabel(BuildContext context, VolumeState state) {
  final l10n = AppLocalizations.of(context);
  final dates = MaterialLocalizations.of(context);
  final week = state.week;
  return state.isThisWeek
      ? l10n.volumeThisWeek
      : l10n.volumeWeekRange(
          dates.formatShortMonthDay(week.toLocalDateTime()),
          dates.formatShortMonthDay(
            week.addDays(DateTime.daysPerWeek - 1).toLocalDateTime(),
          ),
        );
}

class _Week extends StatelessWidget {
  const _Week(this.state, this.week);
  final VolumeState state;
  final WeekVolume week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = volumeScale(week.sets.values);
    // Most sets first; ties in vocabulary order.
    final muscles = [...Muscle.values]
      ..sort((a, b) {
        final bySets = week.setsOf(b).compareTo(week.setsOf(a));
        return bySets != 0 ? bySets : a.index.compareTo(b.index);
      });
    return ListView(
      children: [
        _VolumeModel(
          week,
          semanticLabel: l10n.volumeModelLabel(_weekLabel(context, state)),
        ),
        const _Legend(),
        if (week.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Text(
              state.isThisWeek
                  ? l10n.volumeNoWorkoutsThisWeek
                  : l10n.volumeNoWorkoutsThatWeek,
              textAlign: TextAlign.center,
            ),
          ),
        for (final muscle in muscles)
          ListTile(
            title: Text(l10n.muscleName(muscle)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: VolumeBandBar(sets: week.setsOf(muscle), scale: scale),
            ),
            trailing: Text(l10n.setsText(week.setsOf(muscle))),
            onTap: () => _showMuscle(context, muscle),
          ),
      ],
    );
  }
}

/// The model with each trained muscle in its zone's colour; an untrained
/// one keeps the body's colour. Tapping a muscle opens it.
class _VolumeModel extends StatefulWidget {
  const _VolumeModel(this.week, {required this.semanticLabel});
  final WeekVolume week;
  final String semanticLabel;

  @override
  State<_VolumeModel> createState() => _VolumeModelState();
}

class _VolumeModelState extends State<_VolumeModel> {
  /// Share of the screen height the model takes, leaving the bars in view.
  static const _heightRatio = 1 / 3;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final week = widget.week;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _heightRatio,
      child: switch (context.watch<BodyModelCubit>().state) {
        BodyModelLoading() => const LoadingView(),
        BodyModelFailed() => Center(child: Text(l10n.modelLoadFailed)),
        BodyModelReady(:final model) => ModelViewer(
          model: model,
          partColors: {
            for (final MapEntry(key: muscle, value: sets) in week.sets.entries)
              for (final mesh in muscle.meshNames)
                mesh: VolumeZone.of(sets).color(colors),
          },
          selectable: (part) => muscleOfMesh(part) != null,
          onPartTap: (part) {
            if (muscleOfMesh(part) case final muscle?) {
              _showMuscle(context, muscle);
            }
          },
          semanticLabel: widget.semanticLabel,
        ),
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Gap.sm),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Gap.md,
        children: [
          for (final zone in VolumeZone.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: zone.color(colors)),
                const SizedBox(width: Gap.xs),
                Text(l10n.zoneLabel(zone)),
              ],
            ),
        ],
      ),
    );
  }
}

Future<void> _showMuscle(BuildContext context, Muscle muscle) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlocProvider.value(
        value: context.read<VolumeCubit>(),
        child: _MuscleSheet(muscle),
      ),
    );

/// One muscle in the week shown: its sets, where they came from and its
/// trend.
class _MuscleSheet extends StatelessWidget {
  const _MuscleSheet(this.muscle);
  final Muscle muscle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final state = context.watch<VolumeCubit>().state;
    final week = state.shown;
    if (week == null) return const SizedBox.shrink();
    final sets = week.setsOf(muscle);
    final contributions = week.contributionsTo(muscle);
    return DraggableScrollableSheet(
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          ListTile(
            title: Text(
              l10n.muscleName(muscle),
              style: theme.textTheme.titleLarge,
            ),
            subtitle: Text(
              l10n.volumeMuscleSummary(
                l10n.setsText(sets),
                l10n.zoneLabel(VolumeZone.of(sets)),
              ),
            ),
          ),
          _Header(l10n.volumeContributionsTitle),
          if (contributions.isEmpty)
            ListTile(title: Text(l10n.volumeNoContributions)),
          for (final (:entry, sets: given) in contributions)
            ListTile(
              title: Text(_exerciseName(context, entry)),
              subtitle: Text(
                l10n.volumeContribution(
                  entry.workoutName,
                  dates.formatMediumDate(entry.startedAt.toLocal()),
                ),
              ),
              trailing: Text(l10n.setsText(given)),
            ),
          _Trend(muscle: muscle, state: state),
        ],
      ),
    );
  }

  /// The library's name, custom exercises included; the name stored with
  /// the workout for one no longer there.
  String _exerciseName(BuildContext context, VolumeEntry entry) {
    final catalogue = context.watch<ExerciseCatalogueCubit>().state;
    final known = catalogue is CatalogueReady
        ? catalogue.exercises.where((e) => e.id == entry.exerciseId).firstOrNull
        : null;
    return known?.localized(context).name ?? entry.exerciseName;
  }
}

/// The muscle's sets per week, for Premium; a locked teaser that opens the
/// paywall for everyone else, nothing while that is unknown.
class _Trend extends StatelessWidget {
  const _Trend({required this.muscle, required this.state});

  final Muscle muscle;
  final VolumeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final premium = context.watchPremium();
    if (premium == PremiumStatus.unknown) return const SizedBox.shrink();
    final weeks = state.weeks;
    final sets = [for (final week in weeks) week.setsOf(muscle)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          state.isThisWeek
              ? l10n.volumeTrendTitle(trendWeeks)
              : l10n.volumeTrendTitleUntil(
                  trendWeeks,
                  dates.formatShortMonthDay(
                    state.week
                        .addDays(DateTime.daysPerWeek - 1)
                        .toLocalDateTime(),
                  ),
                ),
        ),
        if (premium == PremiumStatus.free)
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.volumeTrendLocked(trendWeeks)),
            trailing: const Icon(Icons.chevron_right),
            onTap: context.openPaywall,
          )
        else if (!state.hasTrend)
          const LoadingView()
        else
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VolumeTrendChart(
                  sets: sets,
                  semanticLabel: l10n.volumeTrendLabel(
                    l10n.muscleName(muscle),
                    l10n.inlineList(sets.map(l10n.setsText)),
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final week in [weeks.first, weeks.last])
                      Text(
                        dates.formatShortMonthDay(week.start.toLocalDateTime()),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: ListTile(
      title: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
