import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../domain/dashboard.dart';
import 'dashboard_cubit.dart';
import 'dashboard_format.dart';
import 'dashboard_sections.dart';

/// The widest the page grows on a desktop screen.
const _maxPageWidth = 1280.0;

/// The narrowest a tile gets before the grid drops a column.
const _minTileWidth = 200.0;
const _tileColumns = 5;

/// From this width the sections sit two by two.
const _twoColumnWidth = 840.0;

/// The width of the period control.
const _periodWidth = 440.0;

/// The panel's first page: the app's numbers for a period, from what the
/// nightly refresh stored, or for a custom range queried live.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<DashboardCubit>(),
    child: _DashboardView(env: sl<AppEnv>()),
  );
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.env});

  final AppEnv env;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxPageWidth),
            child: ListView(
              padding: const EdgeInsets.all(Gap.md),
              children: [
                _StatusLine(state: state, env: env),
                const SizedBox(height: Gap.md),
                ..._content(context, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, DashboardState state) {
    final cubit = context.read<DashboardCubit>();
    final data = state.data;
    if (data == null) {
      final failure = state.failure;
      if (failure == null) return const [LoadingView()];
      return [
        ErrorView(
          title: 'The dashboard did not load',
          message: dashboardFailureText(failure),
          onRetry: cubit.load,
          retryLabel: 'Retry',
        ),
      ];
    }
    final revenue = RevenueSection(revenue: data.revenue, env: env);
    if (data.hasNoData) {
      return [
        const EmptyView(
          icon: ForgeIcons.showChart,
          title: 'No data yet',
          message:
              'The first Analytics export arrives within a day of linking.',
          card: true,
        ),
        const SizedBox(height: Gap.md),
        revenue,
      ];
    }
    final report = state.report;
    final retention = RetentionSection(
      cohorts: data.retention,
      view: state.retentionView,
      onView: cubit.showRetentionAs,
    );
    return [
      _PeriodControl(state: state),
      const SizedBox(height: Gap.md),
      if (report != null) ...[
        _Tiles(report: report, currency: data.revenue?.currency),
        const SizedBox(height: Gap.md),
        _SectionGrid([
          GrowthSection(growth: report.growth),
          FunnelSection(
            funnel: report.funnel,
            view: state.funnelView,
            onView: cubit.showFunnelAs,
          ),
          retention,
          revenue,
          UsageSection(usage: report.usage),
          QualitySection(quality: report.quality),
        ]),
      ] else ...[
        if (state.customLoading)
          const LoadingView()
        else if (state.customFailure == null)
          const EmptyView(
            icon: ForgeIcons.showChart,
            message: 'No report for this period yet.',
            card: true,
          ),
        const SizedBox(height: Gap.md),
        _SectionGrid([retention, revenue]),
      ],
    ];
  }
}

/// Which project, how fresh the numbers are, and Refresh now.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state, required this.env});

  final DashboardState state;
  final AppEnv env;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    final status = state.data?.status;
    final lastDay = status?.lastDay;
    final problems = [
      if (status case DashboardStatus(
        state: RefreshState.error,
        :final message,
      ))
        'The last refresh failed in part: ${message ?? 'no details'}',
      if (state.refreshFailure case final failure?)
        'Refresh now failed: ${dashboardFailureText(failure)}',
      if (state.failure case final failure? when state.data != null)
        'Reloading failed: ${dashboardFailureText(failure)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${env.isProd ? 'Production' : 'Development'} · updated '
                'nightly · last day: '
                '${lastDay == null ? 'none yet' : dayLabel(lastDay)}',
                style: text.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: state.refreshing
                  ? null
                  : context.read<DashboardCubit>().refresh,
              child: Text(state.refreshing ? 'Refreshing…' : 'Refresh now'),
            ),
          ],
        ),
        if (state.refreshing || (state.loading && state.data != null))
          const LinearProgressIndicator(),
        for (final problem in problems) Text(problem, style: error),
      ],
    );
  }
}

/// 7, 30 or 90 days, or a custom range picked up to the last day.
class _PeriodControl extends StatelessWidget {
  const _PeriodControl({required this.state});

  final DashboardState state;

  Future<void> _pickRange(BuildContext context, DateTime lastDay) async {
    final cubit = context.read<DashboardCubit>();
    // Local dates for the picker; the data's days are UTC midnights.
    DateTime local(DateTime day) => DateTime(day.year, day.month, day.day);
    DateTime utc(DateTime day) => DateTime.utc(day.year, day.month, day.day);
    final last = local(lastDay);
    final shown = state.customRange ?? state.report?.range;
    final picked = await showDateRangePicker(
      context: context,
      // Analytics keeps 14 months.
      firstDate: DateTime(last.year, last.month - 14, last.day),
      lastDate: last,
      initialDateRange: shown == null
          ? null
          : DateTimeRange(start: local(shown.from), end: local(shown.to)),
    );
    if (picked == null) return;
    await cubit.selectRange(DayRange(utc(picked.start), utc(picked.end)));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DashboardCubit>();
    final lastDay = state.data?.status?.lastDay;
    final range = state.customRange ?? state.report?.range;
    final failure = state.customFailure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gap.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _periodWidth),
              child: ForgeSegmentedControl<DashboardPreset?>(
                segments: [
                  for (final preset in DashboardPreset.values)
                    ForgeSegment(value: preset, label: '${preset.days} days'),
                  if (lastDay != null)
                    const ForgeSegment(value: null, label: 'Custom…'),
                ],
                selected: state.customRange == null ? state.preset : null,
                onChanged: (preset) => preset == null
                    ? _pickRange(context, lastDay!)
                    : cubit.selectPreset(preset),
              ),
            ),
            if (range != null)
              Text('${dayLabel(range.from)} – ${dayLabel(range.to)}'),
          ],
        ),
        if (state.customLoading) const LinearProgressIndicator(),
        if (failure != null)
          Text(
            dashboardFailureText(failure),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

/// The ten figures with their change against the period before.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.report, required this.currency});

  final Report report;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / _minTileWidth).floor().clamp(
          1,
          _tileColumns,
        );
        final width = (constraints.maxWidth - Gap.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final tile in DashboardTile.values)
              if (report.tiles[tile] case final value?)
                SizedBox(width: width, child: _tile(tile, value)),
          ],
        );
      },
    );
  }

  Widget _tile(DashboardTile tile, TileValue value) {
    final change = tileChange(tile, value);
    return StatTile.compact(
      label: tileLabel(tile),
      figure: tileFigure(tile, value.value, currency: currency),
      change: change?.text,
      changeIsGood: change?.good,
    );
  }
}

/// The sections two by two, or one under the other when narrow.
class _SectionGrid extends StatelessWidget {
  const _SectionGrid(this.sections);

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.md,
            children: sections,
          );
        }
        return Column(
          spacing: Gap.md,
          children: [
            for (var i = 0; i < sections.length; i += 2)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.md,
                children: [
                  Expanded(child: sections[i]),
                  Expanded(
                    child: i + 1 < sections.length
                        ? sections[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
