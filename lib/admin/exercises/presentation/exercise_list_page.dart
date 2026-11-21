import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../admin_router.dart';
import '../../shell/admin_text.dart';
import '../../shell/filter_column.dart';
import '../../shell/page_header.dart';
import '../../shell/status_tag.dart';
import '../domain/exercise_admin_usecases.dart';
import '../domain/exercise_draft.dart';
import 'exercise_list_cubit.dart';

/// The width of the search field above the table.
const _searchWidth = 320.0;

/// Every exercise of every status: the library's health in one line, the
/// filters in a column on the left, search and the table on the right.
/// Needs `ExerciseListCubit` above it.
class ExerciseListPage extends StatelessWidget {
  const ExerciseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<ExerciseListCubit, ExerciseListState>(
        builder: (context, state) {
          final records = state.records;
          final failure = state.failure;
          final header = PageHeader(
            title: 'Exercises',
            subtitle: records == null
                ? 'Updates live'
                : '${records.length} exercises in every status · updates live',
            trailing: [
              ForgeButton(
                label: 'New exercise',
                onPressed: () => context.go(AdminRoutes.newExercise),
              ),
            ],
          );
          return Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.md,
              children: [
                header,
                if (records == null)
                  Expanded(
                    child: failure == null
                        ? const LoadingView()
                        : ErrorView(
                            title: "Couldn't load exercises",
                            message: failureMessage(failure),
                            onRetry: context.read<ExerciseListCubit>().retry,
                            retryLabel: 'Retry',
                          ),
                  )
                else ...[
                  if (failure != null)
                    MaterialBanner(
                      content: Text(
                        'Live updates stopped: ${failureMessage(failure)} '
                        'Retrying automatically.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: context.read<ExerciseListCubit>().retry,
                          child: const Text('Retry now'),
                        ),
                      ],
                    ),
                  if (state.health case final health?) _HealthLine(health),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Gap.md,
                      children: [
                        _Filters(state: state),
                        Expanded(child: _Table(state: state)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state});

  final ExerciseListState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExerciseListCubit>();
    final counts = state.counts;
    return FilterColumn(
      children: [
        FilterRadios<ExerciseStatus>(
          label: 'Status',
          options: [
            (value: null, label: 'All · ${state.records?.length ?? 0}'),
            for (final status in ExerciseStatus.values)
              (
                value: status,
                label: '${codeLabel(status)} · ${counts[status]}',
              ),
          ],
          selected: state.status,
          onChanged: cubit.filterStatus,
        ),
        FilterDropdown<Muscle>(
          label: 'Main muscle',
          options: _anyOf(Muscle.values),
          selected: state.muscle,
          onChanged: cubit.filterMuscle,
        ),
        FilterDropdown<Equipment>(
          label: 'Equipment',
          options: _anyOf(Equipment.values),
          selected: state.equipment,
          onChanged: cubit.filterEquipment,
        ),
        FilterDropdown<ExerciseSort>(
          label: 'Sort',
          options: const [
            (value: ExerciseSort.popularity, label: 'Popularity'),
            (value: ExerciseSort.name, label: 'Name'),
          ],
          selected: state.sort,
          onChanged: (sort) => cubit.sortBy(sort!),
        ),
      ],
    );
  }

  static List<FilterOption<T>> _anyOf<T extends Coded>(List<T> values) => [
    (value: null, label: 'Any'),
    for (final value in values) (value: value, label: codeLabel(value)),
  ];
}

/// The library's health in one line; Details lists every finding.
class _HealthLine extends StatelessWidget {
  const _HealthLine(this.health);

  final LibraryHealth health;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    final warnings = '${health.warnings.length} warning(s)';
    final summary = health.isHealthy
        ? 'Library health: all library rules pass · $warnings'
        : 'Library health: ${health.errors.length} problem(s), '
              '${health.invalidIds.length} invalid document(s) · $warnings';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
        child: Row(
          spacing: Gap.sm,
          children: [
            Icon(
              health.isHealthy
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              color: health.isHealthy ? colors.success : colors.danger,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary, style: text.labelLarge),
                  Text(
                    'Not enforced on save: fix these across exercises, then '
                    'they clear.',
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            ForgeButton(
              label: 'Details',
              variant: ForgeButtonVariant.outline,
              size: ForgeButtonSize.small,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => _HealthDialog(health),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthDialog extends StatelessWidget {
  const _HealthDialog(this.health);

  final LibraryHealth health;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Library health'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.xs,
          children: [
            if (health.isHealthy && health.warnings.isEmpty)
              const Text('Every library rule passes.'),
            for (final id in health.invalidIds)
              Text('$id breaks the rules of a single exercise; open it.'),
            for (final error in health.errors) Text(error),
            for (final warning in health.warnings) Text('Warning: $warning'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Search, then the matching exercises as a table.
class _Table extends StatelessWidget {
  const _Table({required this.state});

  final ExerciseListState state;

  @override
  Widget build(BuildContext context) {
    final visible = state.visible;
    final muted = ForgeStyle.of(context).colors.inkMuted;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: Gap.md,
              children: [
                SizedBox(
                  width: _searchWidth,
                  child: _Search(query: state.query),
                ),
                Text(
                  'Showing ${visible.length} of ${state.records?.length ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            const _HeaderRow(),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? const EmptyView(
                      title: 'No results',
                      message: 'No exercise matches.',
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _ExerciseRow(visible[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The search field, starting from the query kept in the cubit.
class _Search extends StatefulWidget {
  const _Search({required this.query});

  final String query;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  late final _controller = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ForgeSearchField(
    hint: 'Search name, alias or id',
    clearLabel: 'Clear search',
    controller: _controller,
    onChanged: context.read<ExerciseListCubit>().search,
  );
}

/// Column widths of the table, as flex factors.
const _columns = [
  ('Name', 3),
  ('Id', 3),
  ('Status', 1),
  ('Main muscles', 2),
  ('Equipment', 3),
  ('Family / rank', 2),
  ('Popularity', 1),
  ('Updated', 2),
];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    return _Cells([
      for (final (label, _) in _columns) Text(label, style: style),
    ]);
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow(this.record);

  final ExerciseRecord record;

  @override
  Widget build(BuildContext context) {
    final draft = record.draft;
    final style = ForgeStyle.of(context);
    return InkWell(
      onTap: () => context.go(AdminRoutes.exercise(record.id)),
      child: _Cells([
        Text(draft.name, style: Theme.of(context).textTheme.labelLarge),
        Text(record.id, style: style.data),
        Align(alignment: Alignment.centerLeft, child: StatusTag(draft.status)),
        Text(codeLabels(draft.mainMuscles)),
        Text(
          [
            codeLabels(draft.equipment),
            for (final set in draft.equipmentAlternatives) codeLabels(set),
          ].join(' | '),
        ),
        Text('${draft.family} / ${draft.familyRank ?? '-'}'),
        Text('${draft.popularity ?? '-'}'),
        Text(dateTimeLabel(record.updatedAt)),
      ]),
    );
  }
}

class _Cells extends StatelessWidget {
  const _Cells(this.cells);

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        children: [
          for (final (index, cell) in cells.indexed)
            Expanded(
              flex: _columns[index].$2,
              child: Padding(
                padding: const EdgeInsets.only(right: Gap.sm),
                child: cell,
              ),
            ),
        ],
      ),
    );
  }
}
