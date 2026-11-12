import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_program.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../../admin_router.dart';
import '../../shell/admin_nav.dart';
import '../../shell/admin_text.dart';
import '../domain/program_admin_usecases.dart';
import '../domain/program_draft.dart';
import 'program_list_cubit.dart';

/// The width of the search field.
const _fieldWidth = 240.0;

/// Every ready-made program of every status, by catalogue order, with
/// search, a status filter and the catalogue's health. Needs
/// `ProgramListCubit` above it.
class ProgramListPage extends StatelessWidget {
  const ProgramListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programs'),
        actions: const [AdminNav()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AdminRoutes.newProgram),
        icon: const Icon(Icons.add),
        label: const Text('New program'),
      ),
      body: BlocBuilder<ProgramListCubit, ProgramListState>(
        builder: (context, state) {
          final records = state.records;
          final failure = state.failure;
          if (records == null) {
            return failure == null
                ? const LoadingView()
                : ErrorView(
                    message: failureMessage(failure),
                    onRetry: context.read<ProgramListCubit>().retry,
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
                      onPressed: context.read<ProgramListCubit>().retry,
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
                    ? const EmptyView(message: 'No program matches.')
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _ProgramRow(visible[index]),
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

  final ProgramListState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProgramListCubit>();
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
                labelText: 'Search name or id',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: cubit.search,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel(this.health);

  final CatalogueHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        health.isHealthy ? Icons.check_circle_outline : Icons.info_outline,
        color: health.isHealthy ? scheme.primary : scheme.tertiary,
      ),
      title: Text(
        health.isHealthy
            ? 'Catalogue health: all catalogue rules pass'
            : 'Catalogue health: ${health.errors.length} problem(s)',
      ),
      subtitle: const Text(
        'Unique names and orders; live programs are exactly $freePrograms '
        'free and $premiumPrograms premium. Not enforced on save: fix these '
        'across programs, then they clear.',
      ),
      trailing: health.isHealthy
          ? null
          : TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Catalogue health'),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final error in health.errors) Text(error),
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
  ('Order', 1),
  ('Name', 3),
  ('Id', 3),
  ('Status', 1),
  ('Access', 1),
  ('Days', 1),
  ('Level', 1),
  ('Goal', 2),
  ('Equipment profile', 2),
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

class _ProgramRow extends StatelessWidget {
  const _ProgramRow(this.record);

  final ProgramRecord record;

  @override
  Widget build(BuildContext context) {
    final draft = record.draft;
    final scheme = Theme.of(context).colorScheme;
    String label(Coded? value) => value == null ? '-' : codeLabel(value);
    return InkWell(
      onTap: () => context.go(AdminRoutes.program(record.id)),
      child: _Cells([
        Text('${draft.order ?? '-'}'),
        Text(draft.textOf(CatalogueProgram.fallbackLanguage).name),
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
        Text(draft.premium ? 'Premium' : 'Free'),
        Text('${record.daysPerWeek ?? '-'}'),
        Text(label(draft.level)),
        Text(label(draft.goal)),
        Text(label(draft.equipmentProfile)),
        Text(dateTimeLabel(record.version.card)),
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
