import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';
import 'history_list_cubit.dart';
import 'start_workout.dart';
import 'workout_text.dart';

/// The finished workouts, newest first, a page at a time.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<HistoryListCubit>(),
    child: const _HistoryView(),
  );
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<HistoryListCubit>();
    return BlocConsumer<HistoryListCubit, HistoryListState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.historyWritesRejected)));
        cubit.rejectionShown();
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(l10n.historyTitle)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go(Routes.historyNew),
          icon: const Icon(Icons.add),
          label: Text(l10n.historyAddPast),
        ),
        body: switch (state.status) {
          HistoryListStatus.loading => const LoadingView(),
          HistoryListStatus.failure => ErrorView(
            message: l10n.historyLoadFailed,
            retryLabel: l10n.retry,
            onRetry: cubit.retry,
          ),
          HistoryListStatus.ready when state.workouts.isEmpty => EmptyView(
            message: l10n.historyEmpty,
            action: ForgeButton(
              label: l10n.workoutStartWorkout,
              onPressed: () => startFreeWorkout(context),
            ),
          ),
          HistoryListStatus.ready => _Workouts(state),
        },
      ),
    );
  }
}

class _Workouts extends StatelessWidget {
  const _Workouts(this.state);
  final HistoryListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workouts = state.workouts;
    return ListView.builder(
      // Clear of the button.
      padding: const EdgeInsets.only(bottom: Gap.xl * 2),
      itemCount: workouts.length + (state.more ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < workouts.length) return _WorkoutTile(workouts[index]);
        return Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: state.loadingMore
              ? const Center(child: CircularProgressIndicator())
              : OutlinedButton(
                  onPressed: context.read<HistoryListCubit>().loadMore,
                  child: Text(l10n.historyLoadOlder),
                ),
        );
      },
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile(this.workout);
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final summary = summarizeWorkout(workout, const []);
    final start = workout.startedAt;
    final details = [
      '${dates.formatMediumDate(start)} '
          '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
      l10n.durationMinutes(summary.duration),
      l10n.historySetCount(summary.setCount),
      if (summary.volumeKg > 0) l10n.weightText(summary.volumeKg, unit),
    ];
    return ListTile(
      title: Text(workout.name),
      subtitle: Text(details.join(' · ')),
      onTap: () => context.go(Routes.historyWorkout(workout.id)),
    );
  }
}
