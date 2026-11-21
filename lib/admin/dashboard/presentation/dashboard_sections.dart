import 'package:flutter/material.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../domain/dashboard.dart';
import 'dashboard_cubit.dart';
import 'dashboard_format.dart';

/// The width of a section's view toggle.
const _toggleWidth = 240.0;

/// Daily active and new users over the period, one chart each.
class GrowthSection extends StatelessWidget {
  const GrowthSection({super.key, required this.growth});

  final List<DayCount> growth;

  @override
  Widget build(BuildContext context) {
    return SectionCard.plain(
      title: 'Growth',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          _LineOverTime(
            title: 'Daily active users',
            points: [
              for (final d in growth)
                if (d.active case final active?)
                  (day: d.day, value: active.toDouble()),
            ],
            format: countLabel,
          ),
          _LineOverTime(
            title: 'New users',
            points: [
              for (final d in growth)
                if (d.newUsers case final count?)
                  (day: d.day, value: count.toDouble()),
            ],
            format: countLabel,
          ),
        ],
      ),
    );
  }
}

/// A Forge line chart of dated values; a line needs two points.
class _LineOverTime extends StatelessWidget {
  const _LineOverTime({
    required this.title,
    required this.points,
    required this.format,
  });

  final String title;
  final List<({DateTime day, double value})> points;
  final String Function(double value) format;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return Text('$title: too few days to draw.');
    return Chart.line(
      title: title,
      values: [for (final point in points) point.value],
      pointLabel: (i) =>
          '${format(points[i].value)} · ${shortDayLabel(points[i].day)}',
      startLabel: shortDayLabel(points.first.day),
      endLabel: shortDayLabel(points.last.day),
      semanticLabel:
          '$title from ${dayLabel(points.first.day)} '
          'to ${dayLabel(points.last.day)}',
    );
  }
}

/// The period's new users through the steps to paying.
class FunnelSection extends StatelessWidget {
  const FunnelSection({
    super.key,
    required this.funnel,
    required this.view,
    required this.onView,
  });

  final Funnel funnel;
  final FunnelView view;
  final ValueChanged<FunnelView> onView;

  @override
  Widget build(BuildContext context) {
    final f = funnel;
    final steps = [
      ('Installed', f.installed),
      ('Onboarding complete', f.onboardingComplete),
      ('First workout', f.firstWorkout),
      ('Paywall seen', f.paywallSeen),
      ('Trial started', f.trialStarted),
      ('Paid', f.paid),
    ];
    double? share(int? part, int? whole) =>
        part == null || whole == null || whole == 0 ? null : part / whole;
    return SectionCard.plain(
      title: 'Funnel',
      note: "The period's new users",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          _Toggle(
            segments: const [
              ForgeSegment(value: FunnelView.bars, label: 'Bars'),
              ForgeSegment(value: FunnelView.table, label: 'Table'),
            ],
            selected: view,
            onChanged: onView,
          ),
          if (view == FunnelView.bars)
            for (final (label, users) in steps)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Gap.xs,
                children: [
                  FactRow(
                    label: label,
                    value:
                        '${countLabel(users)} · '
                        '${shareLabel(share(users, f.installed))} of installs',
                  ),
                  Progress.track(value: share(users, f.installed) ?? 0),
                ],
              )
          else
            _Table(
              columns: const [
                'Step',
                'Users',
                'Of installs',
                'From step before',
              ],
              rows: [
                for (final (i, (label, users)) in steps.indexed)
                  [
                    label,
                    countLabel(users),
                    shareLabel(share(users, f.installed)),
                    i == 0 ? '' : shareLabel(share(users, steps[i - 1].$2)),
                  ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Day 1, 7 and 30 of the last weekly install cohorts.
class RetentionSection extends StatelessWidget {
  const RetentionSection({
    super.key,
    required this.cohorts,
    required this.view,
    required this.onView,
  });

  /// Null while never stored.
  final List<Cohort>? cohorts;
  final RetentionView view;
  final ValueChanged<RetentionView> onView;

  @override
  Widget build(BuildContext context) {
    final cohorts = this.cohorts;
    return SectionCard.plain(
      title: 'Retention',
      note: 'Weekly install cohorts',
      child: cohorts == null || cohorts.isEmpty
          ? const Text('No cohorts stored yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.md,
              children: [
                _Toggle(
                  segments: const [
                    ForgeSegment(value: RetentionView.table, label: 'Table'),
                    ForgeSegment(value: RetentionView.curves, label: 'Curves'),
                  ],
                  selected: view,
                  onChanged: onView,
                ),
                if (view == RetentionView.table)
                  _Table(
                    columns: const [
                      'Install week',
                      'Users',
                      'Day 1',
                      'Day 7',
                      'Day 30',
                    ],
                    rows: [
                      for (final c in cohorts)
                        [
                          dayLabel(c.week),
                          countLabel(c.users),
                          for (final share in [c.d1, c.d7, c.d30])
                            share == null ? '' : shareLabel(share),
                        ],
                    ],
                  )
                else
                  for (final (title, share) in [
                    ('Day 1', (Cohort c) => c.d1),
                    ('Day 7', (Cohort c) => c.d7),
                    ('Day 30', (Cohort c) => c.d30),
                  ])
                    // The cohorts whose share is known, by install week.
                    _LineOverTime(
                      title: title,
                      points: [
                        for (final c in cohorts)
                          if (share(c) case final value?)
                            (day: c.week, value: value),
                      ],
                      format: shareLabel,
                    ),
              ],
            ),
    );
  }
}

/// RevenueCat's overview, the same whatever the period.
class RevenueSection extends StatelessWidget {
  const RevenueSection({super.key, required this.revenue, required this.env});

  /// Null while never stored.
  final RevenueSnapshot? revenue;
  final AppEnv env;

  @override
  Widget build(BuildContext context) {
    final r = revenue;
    return SectionCard.plain(
      title: 'Revenue',
      child: !env.isProd
          ? const Text(
              'RevenueCat has one project, so revenue is shown on the '
              'production panel only.',
            )
          : r == null
          ? const Text('No revenue snapshot stored yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                FactRow(label: 'MRR', value: moneyLabel(r.mrr, r.currency)),
                FactRow(
                  label: 'Revenue 28 days',
                  value: moneyLabel(r.revenue28d, r.currency),
                ),
                FactRow(
                  label: 'Active subscriptions',
                  value: countLabel(r.activeSubscriptions),
                ),
                FactRow(
                  label: 'Active trials',
                  value: countLabel(r.activeTrials),
                ),
              ],
            ),
    );
  }
}

class UsageSection extends StatelessWidget {
  const UsageSection({super.key, required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context) {
    final u = usage;
    return SectionCard.plain(
      title: 'Usage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          FactRow(label: 'Program starts', value: countLabel(u.programStarts)),
          FactRow(
            label: 'Workouts per active user',
            value: u.workoutsPerActiveUser?.toStringAsFixed(1) ?? unknown,
          ),
          FactRow(
            label: 'Custom exercises created',
            value: countLabel(u.customExercisesCreated),
          ),
          FactRow(label: 'Weights logged', value: countLabel(u.weightsLogged)),
          FactRow(
            label: 'Notifications opened',
            value: countLabel(u.notificationsOpened),
          ),
          FactRow(
            label: 'Most started program',
            value: switch (u.topProgramId) {
              null => 'None',
              final id => '$id · ${countLabel(u.topProgramStarts)} starts',
            },
          ),
        ],
      ),
    );
  }
}

class QualitySection extends StatelessWidget {
  const QualitySection({super.key, required this.quality});

  final Quality quality;

  @override
  Widget build(BuildContext context) {
    final q = quality;
    final issues = q.topIssues;
    return SectionCard.plain(
      title: 'Quality',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          FactRow(
            label: 'Crash-free users',
            value: shareLabel(q.crashFreeUsers),
          ),
          FactRow(label: 'Handled errors', value: countLabel(q.handledErrors)),
          FactRow(
            label: 'Top issues',
            value: switch (issues) {
              null => unknown,
              [] => 'None',
              _ => '',
            },
          ),
          for (final issue in issues ?? const <Issue>[])
            Text('${issue.title} · ${countLabel(issue.users)} users'),
        ],
      ),
    );
  }
}

/// A label and its figure on one line.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.md,
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: ForgeStyle.of(context).data,
          ),
        ),
      ],
    );
  }
}

class _Toggle<T> extends StatelessWidget {
  const _Toggle({
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<ForgeSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _toggleWidth),
      child: ForgeSegmentedControl<T>(
        segments: segments,
        selected: selected,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Text cells under their column names; scrolls sideways when narrow.
class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final (i, name) in columns.indexed)
            DataColumn(label: Text(name), numeric: i > 0),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
        ],
      ),
    );
  }
}
