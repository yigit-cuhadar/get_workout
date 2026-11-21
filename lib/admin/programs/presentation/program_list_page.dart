import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_program.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../../admin_router.dart';
import '../../shell/admin_text.dart';
import '../../shell/filter_column.dart';
import '../../shell/page_header.dart';
import '../../shell/status_tag.dart';
import '../domain/program_admin_usecases.dart';
import '../domain/program_draft.dart';
import 'access_tag.dart';
import 'program_list_cubit.dart';

/// The width of the search field above the table.
const _searchWidth = 320.0;

/// Every ready-made program of every status, by catalogue order: the
/// catalogue's health in one line, the filters in a column on the left,
/// search and the table on the right. Needs `ProgramListCubit` above it.
class ProgramListPage extends StatelessWidget {
  const ProgramListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<ProgramListCubit, ProgramListState>(
        builder: (context, state) {
          final records = state.records;
          final failure = state.failure;
          final header = PageHeader(
            title: 'Programs',
            subtitle: records == null
                ? 'Updates live'
                : '${records.length} ready-made programs, by catalogue '
                      'order · updates live',
            trailing: [
              ForgeButton(
                label: 'New program',
                onPressed: () => context.go(AdminRoutes.newProgram),
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
                            title: "Couldn't load programs",
                            message: failureMessage(failure),
                            onRetry: context.read<ProgramListCubit>().retry,
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
                          onPressed: context.read<ProgramListCubit>().retry,
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

  final ProgramListState state;

  @override
  Widget build(BuildContext context) {
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
          onChanged: context.read<ProgramListCubit>().filterStatus,
        ),
      ],
    );
  }
}

/// The catalogue's health and its split of live programs in one line;
/// Details lists every problem.
class _HealthLine extends StatelessWidget {
  const _HealthLine(this.health);

  final CatalogueHealth health;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    final live = 'live: ${health.liveFree} free, ${health.livePremium} premium';
    final summary = health.isHealthy
        ? 'Catalogue health: all catalogue rules pass · $live'
        : 'Catalogue health: ${health.errors.length} problem(s) · $live';
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
                    'Unique names and orders; live programs are exactly '
                    '$freePrograms free and $premiumPrograms premium. Not '
                    'enforced on save: fix these across programs, then they '
                    'clear.',
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            if (!health.isHealthy)
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

  final CatalogueHealth health;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catalogue health'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.xs,
          children: [for (final error in health.errors) Text(error)],
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

/// Search, then the matching programs as a table.
class _Table extends StatelessWidget {
  const _Table({required this.state});

  final ProgramListState state;

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
                      message: 'No program matches.',
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _ProgramRow(visible[index]),
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
    hint: 'Search name or id',
    clearLabel: 'Clear search',
    controller: _controller,
    onChanged: context.read<ProgramListCubit>().search,
  );
}

/// Column widths of the table, as flex factors.
const _columns = [
  ('Order', 1),
  ('Name', 3),
  ('Id', 3),
  ('Status', 1),
  ('Access', 1),
  ('Days', 1),
  ('Level', 2),
  ('Goal', 2),
  ('Equipment profile', 2),
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

class _ProgramRow extends StatelessWidget {
  const _ProgramRow(this.record);

  final ProgramRecord record;

  @override
  Widget build(BuildContext context) {
    final draft = record.draft;
    final style = ForgeStyle.of(context);
    String label(Coded? value) => value == null ? '-' : codeLabel(value);
    return InkWell(
      onTap: () => context.go(AdminRoutes.program(record.id)),
      child: _Cells([
        Text('${draft.order ?? '-'}'),
        Text(
          draft.textOf(CatalogueProgram.fallbackLanguage).name,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(record.id, style: style.data),
        Align(alignment: Alignment.centerLeft, child: StatusTag(draft.status)),
        Align(
          alignment: Alignment.centerLeft,
          child: AccessTag(premium: draft.premium),
        ),
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
