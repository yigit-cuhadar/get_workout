import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/cardio_session.dart';
import 'cardio_list_cubit.dart';
import 'cardio_text.dart';
import 'weekly_cardio_chart.dart';

/// The weekly chart, then every session grouped by week.
class CardioListPage extends StatelessWidget {
  const CardioListPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<CardioListCubit>(),
    child: const _CardioListView(),
  );
}

class _CardioListView extends StatelessWidget {
  const _CardioListView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<CardioListCubit>().state;
    final hasSessions = state.sessions.isNotEmpty;
    void log() => context.go(Routes.cardioNew);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cardioTitle)),
      floatingActionButton: hasSessions
          ? FloatingActionButton.extended(
              onPressed: log,
              icon: const Icon(Icons.add),
              label: Text(l10n.cardioLog),
            )
          : null,
      body: switch (state.status) {
        CardioListStatus.loading => const LoadingView(),
        CardioListStatus.failure => ErrorView(
          message: l10n.cardioLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<CardioListCubit>().retry,
        ),
        CardioListStatus.ready when !hasSessions => EmptyView(
          message: l10n.cardioEmpty,
          action: ForgeButton(label: l10n.cardioLog, onPressed: log),
        ),
        CardioListStatus.ready => _Sessions(state),
      },
    );
  }
}

class _Sessions extends StatelessWidget {
  const _Sessions(this.state);
  final CardioListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: WeeklyCardioChart(weeks: state.chart),
        ),
        for (final week in state.weeks) ...[
          ListTile(
            dense: true,
            title: Text(
              l10n.cardioWeekOf(dates.formatShortMonthDay(week.start)),
            ),
            trailing: Text(l10n.cardioMinutesOf(week.duration)),
          ),
          for (final session in week.sessions) _SessionTile(session),
        ],
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile(this.session);
  final CardioSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => distanceUnitFor(cubit.state.settings.lengthUnit),
    );
    final distance = session.distanceKm;
    final details = [
      '${dates.formatMediumDate(session.date)} '
          '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(session.date))}',
      formatDuration(session.duration),
      if (distance != null) l10n.distanceText(distance, unit),
      ?l10n.rateText(session, unit),
    ];
    return ListTile(
      title: Text(l10n.typeName(session.type)),
      subtitle: Text(details.join(' · ')),
      onTap: () => context.go(Routes.cardioSession(session.id!)),
    );
  }
}
