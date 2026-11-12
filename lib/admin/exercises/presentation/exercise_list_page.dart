import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../admin_router.dart';
import '../../shell/admin_nav.dart';
import '../../shell/admin_text.dart';
import '../domain/exercise_admin_usecases.dart';
import '../domain/exercise_draft.dart';
import 'exercise_list_cubit.dart';

/// The width of a search or filter field.
const _fieldWidth = 240.0;

/// Every exercise of every status, with search, filters and the library's
/// health. Needs `ExerciseListCubit` above it.
class ExerciseListPage extends StatelessWidget {
  const ExerciseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercises'),
        actions: const [AdminNav()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AdminRoutes.newExercise),
        icon: const Icon(Icons.add),
        label: const Text('New exercise'),
      ),
      body: BlocBuilder<ExerciseListCubit, ExerciseListState>(
        builder: (context, state) {
          final records = state.records;
          final failure = state.failure;
          if (records == null) {
            return failure == null
                ? const LoadingView()
                : ErrorView(
                    message: failureMessage(failure),
                    onRetry: context.read<ExerciseListCubit>().retry,
                  );
          }
          final visible = state.visible;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              _Filters(state: state),
              if (state.health case final health?) _HealthPanel(health),
              const _HeaderRow(),
              const Divider(height: 1),
              Expanded(
                child: visible.isEmpty
                    ? const EmptyView(message: 'No exercise matches.')
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _ExerciseRow(visible[index]),
                      ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: Text('All (${state.records?.length ?? 0})'),
            selected: state.status == null,
            onSelected: (_) => cubit.filterStatus(null),
          ),
          for (final status in ExerciseStatus.values)
            ChoiceChip(
              label: Text('${codeLabel(status)} (${counts[status]})'),
              selected: state.status == status,
              onSelected: (_) => cubit.filterStatus(status),
            ),
          SizedBox(
            width: _fieldWidth,
            child: TextFormField(
              initialValue: state.query,
              decoration: const InputDecoration(
                labelText: 'Search name, alias or id',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: cubit.search,
            ),
          ),
          _Picker<Muscle>(
            label: 'Main muscle',
            values: Muscle.values,
            value: state.muscle,
            onChanged: cubit.filterMuscle,
          ),
          _Picker<Equipment>(
            label: 'Equipment',
            values: Equipment.values,
            value: state.equipment,
            onChanged: cubit.filterEquipment,
          ),
          SegmentedButton<ExerciseSort>(
            segments: const [
              ButtonSegment(
                value: ExerciseSort.popularity,
                label: Text('By popularity'),
              ),
              ButtonSegment(value: ExerciseSort.name, label: Text('By name')),
            ],
            selected: {state.sort},
            onSelectionChanged: (sort) => cubit.sortBy(sort.single),
          ),
        ],
      ),
    );
  }
}

class _Picker<T extends Coded> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T? value;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _fieldWidth,
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(child: Text('Any')),
          for (final value in values)
            DropdownMenuItem(value: value, child: Text(codeLabel(value))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel(this.health);

  final LibraryHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = health.isHealthy
        ? 'Library health: all library rules pass'
        : 'Library health: ${health.errors.length} problem(s), '
              '${health.invalidIds.length} invalid document(s)';
    return ListTile(
      leading: Icon(
        health.isHealthy ? Icons.check_circle_outline : Icons.info_outline,
        color: health.isHealthy ? scheme.primary : scheme.tertiary,
      ),
      title: Text(summary),
      subtitle: Text(
        '${health.warnings.length} warning(s). Not enforced on save: '
        'fix these across exercises, then they clear.',
      ),
      trailing: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Library health'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final id in health.invalidIds)
                    Text('$id breaks the rules of a single exercise; open it.'),
                  for (final error in health.errors) Text(error),
                  for (final warning in health.warnings)
                    Text('Warning: $warning'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: const Text('Details'),
      ),
    );
  }
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
    final style = Theme.of(context).textTheme.labelLarge;
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.go(AdminRoutes.exercise(record.id)),
      child: _Cells([
        Text(draft.name),
        Text(record.id),
        Text(
          codeLabel(draft.status),
          style: TextStyle(
            color: switch (draft.status) {
              ExerciseStatus.live => scheme.primary,
              ExerciseStatus.draft => scheme.tertiary,
              ExerciseStatus.retired => scheme.outline,
            },
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
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
