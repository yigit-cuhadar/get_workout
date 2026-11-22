import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_week.dart';
import 'cardio_list_cubit.dart';
import 'cardio_text.dart';

/// This week's summary in a band, the 12-week chart, then every session
/// grouped by week; Log cardio stays at the bottom.
class CardioListPage extends StatelessWidget {
  const CardioListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = sl<CardioListCubit>();
    return BlocProvider.value(
      value: cubit,
      child: FirstWeekdayListener(
        created: cubit.firstWeekday,
        onChanged: (context, firstWeekday) =>
            context.read<CardioListCubit>().changeFirstWeekday(firstWeekday),
        child: const _CardioListView(),
      ),
    );
  }
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
  /// sleeps, without a new snapshot to recompute it; the health store may
  /// have new workouts.
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
        showForgeSnackbar(
          context,
          message: l10n.cardioWritesRejected,
          error: true,
        );
        _cubit.rejectionShown();
      },
      builder: (context, state) => Scaffold(
        appBar: ForgeAppBar(title: l10n.cardioTitle),
        body: switch (state.status) {
          CardioListStatus.loading => const _Loading(),
          CardioListStatus.failure => ErrorView(
            title: l10n.cardioLoadFailed,
            message: l10n.loadFailedDetail,
            retryLabel: l10n.retry,
            onRetry: _cubit.retry,
          ),
          CardioListStatus.ready => _Sessions(state),
        },
        bottomNavigationBar: state.status == CardioListStatus.ready
            ? ForgeBottomActionBar(
                primary: ForgeButton(
                  label: l10n.cardioLog,
                  size: ForgeButtonSize.large,
                  onPressed: () => context.go(Routes.cardioNew),
                ),
              )
            : null,
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        FeaturedCard.loading(eyebrow: l10n.cardioThisWeek),
        const SizedBox(height: Gap.md),
        Chart.loading(
          title: l10n.cardioChartTitle,
          detail: l10n.cardioChartDetail,
        ),
        const SizedBox(height: Gap.md),
        const ListRowCard(
          children: [
            ListRow.loading(),
            ListRow.loading(index: 1),
            ListRow.loading(index: 2),
          ],
        ),
      ],
    );
  }
}

/// The band and the chart, then a header and the sessions of each week,
/// built lazily; with no session at all the band and a message.
class _Sessions extends StatelessWidget {
  const _Sessions(this.state);
  final CardioListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final thisWeek = state.chart.last;
    final rows = <WidgetBuilder>[
      (_) => _ThisWeek(thisWeek, empty: state.sessions.isEmpty),
      if (state.sessions.isEmpty)
        (_) => EmptyView(
          icon: ForgeIcons.directionsRun,
          title: l10n.cardioEmpty,
          message: l10n.cardioEmptyDetail,
          compact: true,
          card: true,
        )
      else
        (_) => _WeeksChart(state.chart),
      for (final week in state.weeks) ...[
        (_) => SectionLabel(
          week.start == thisWeek.start
              ? l10n.cardioThisWeek
              : l10n.dateRange(
                  CalendarDate.of(week.start),
                  CalendarDate.of(week.start).addDays(6),
                ),
        ),
        (_) => ListRowCard(
          children: [for (final session in week.sessions) _Row(session)],
        ),
      ],
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(Gap.md),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
      itemBuilder: (context, index) => rows[index](context),
    );
  }
}

/// The current week's distance and minutes, and its session count.
class _ThisWeek extends StatelessWidget {
  const _ThisWeek(this.week, {required this.empty});
  final CardioWeek week;

  /// No session at all yet.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => distanceUnitFor(cubit.state.settings.lengthUnit),
    );
    final distance = week.distanceKm;
    final minutes = l10n.cardioMinutesOf(week.duration);
    final count = week.sessions.length;
    return FeaturedCard(
      form: FeaturedCardForm.band,
      eyebrow: l10n.cardioThisWeek,
      title: distance != null
          ? '${l10n.distanceText(distance, unit)} · $minutes'
          // A week without sessions still reads in both units.
          : count == 0
          ? '${l10n.distanceText(0, unit)} · $minutes'
          : minutes,
      when: empty ? l10n.cardioNoSessionsYet : l10n.cardioSessions(count),
    );
  }
}

/// Minutes per week over the last 12, this week in accent.
class _WeeksChart extends StatelessWidget {
  const _WeeksChart(this.weeks);
  final List<CardioWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = DateFormat.MMMd(l10n.localeName);
    final last = weeks.length - 1;
    int minutes(CardioWeek week) => (week.duration.inSeconds / 60).round();
    return Chart.bar(
      title: l10n.cardioChartTitle,
      detail: l10n.cardioChartDetail,
      bars: [
        for (final (i, week) in weeks.indexed)
          ChartBar(
            // Every other week, counted back from this one.
            label: (last - i).isEven ? label.format(week.start) : '',
            value: week.duration.inMinutes.toDouble(),
            // An empty week has no figure over its bar.
            valueLabel: minutes(week) == 0 ? null : '${minutes(week)}',
            tooltip: l10n.cardioChartTooltip(
              l10n.cardioMinutes(minutes(week)),
              label.format(week.start),
            ),
          ),
      ],
      current: last,
      smallLabels: true,
      semanticLabel: l10n.cardioChartCaption,
    );
  }
}

/// A session: its type and distance, the day and minutes, the health
/// store's tag on one read from there; it opens the session.
class _Row extends StatelessWidget {
  const _Row(this.session);
  final CardioSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => distanceUnitFor(cubit.state.settings.lengthUnit),
    );
    final distance = session.distanceKm;
    final type = l10n.typeName(session.type);
    return ListRow(
      title: distance == null
          ? type
          : '$type · ${l10n.distanceText(distance, unit)}',
      detail:
          '${l10n.planDate(CalendarDate.of(session.date))} · '
          '${l10n.cardioMinutesOf(session.duration)}',
      trailing: session.fromHealth
          ? ForgeTag(
              healthSourceName(context, session),
              kind: ForgeTagKind.source,
            )
          : null,
      end: ListRowEnd.chevron,
      onTap: () => context.go(Routes.cardioSession(session.id!)),
    );
  }
}
