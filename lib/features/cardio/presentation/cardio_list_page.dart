import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_week.dart';
import 'cardio_list_cubit.dart';
import 'cardio_text.dart';
import 'weekly_cardio_chart.dart';

/// This week's summary, the 12-week chart, then every session grouped by
/// week; Log cardio stays at the bottom.
class CardioListPage extends StatelessWidget {
  const CardioListPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<CardioListCubit>(),
    child: const _CardioListView(),
  );
}

class _CardioListView extends StatefulWidget {
  const _CardioListView();

  @override
  State<_CardioListView> createState() => _CardioListViewState();
}

class _CardioListViewState extends State<_CardioListView> {
  late final CardioListCubit _cubit = context.read<CardioListCubit>();

  late final AppLifecycleListener _lifecycle;

  /// The chart's current week moves on while the page is away or the app
  /// sleeps, without a new snapshot to recompute it.
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
    return BlocConsumer<CardioListCubit, CardioListState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.cardioWritesRejected)));
        _cubit.rejectionShown();
      },
      builder: (context, state) {
        final ready = state.status == CardioListStatus.ready;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.cardioTitle)),
          body: switch (state.status) {
            CardioListStatus.loading => const LoadingView(),
            CardioListStatus.failure => ErrorView(
              message: l10n.cardioLoadFailed,
              retryLabel: l10n.retry,
              onRetry: _cubit.retry,
            ),
            CardioListStatus.ready when state.sessions.isEmpty => EmptyView(
              message: l10n.cardioEmpty,
            ),
            CardioListStatus.ready => _Sessions(state),
          },
          bottomNavigationBar: ready
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: ForgeButton(
                      label: l10n.cardioLog,
                      onPressed: () => context.go(Routes.cardioNew),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// The summary and the chart, then a header and the sessions of each week,
/// built lazily.
class _Sessions extends StatelessWidget {
  const _Sessions(this.state);
  final CardioListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final rows = <WidgetBuilder>[
      (_) => _ThisWeek(state.chart.last),
      (_) => Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: WeeklyCardioChart(weeks: state.chart),
      ),
      for (final week in state.weeks) ...[
        (_) => ListTile(
          dense: true,
          title: Text(l10n.cardioWeekOf(dates.formatShortMonthDay(week.start))),
          trailing: Text(l10n.cardioMinutesOf(week.duration)),
        ),
        for (final session in week.sessions) (_) => _SessionTile(session),
      ],
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](context),
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

/// Minutes, sessions and distance of the current week, the chart's last.
class _ThisWeek extends StatelessWidget {
  const _ThisWeek(this.week);
  final CardioWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => distanceUnitFor(cubit.state.settings.lengthUnit),
    );
    final distance = week.distanceKm;
    return ListTile(
      title: Text(l10n.cardioThisWeek),
      subtitle: Text(
        l10n.cardioMinutesOf(week.duration),
        style: theme.textTheme.headlineSmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(l10n.cardioSessions(week.sessions.length)),
          if (distance != null) Text(l10n.distanceText(distance, unit)),
        ],
      ),
    );
  }
}
