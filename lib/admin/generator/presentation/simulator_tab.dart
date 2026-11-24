import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/generator/domain/generator_repository.dart';
import '../../../features/programs/domain/program.dart';
import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import '../domain/simulation.dart';
import 'generator_rules_cubit.dart';
import 'generator_simulator_cubit.dart';
import 'generator_sizes.dart';
import 'rule_fields.dart';
import 'rules_text.dart';

final _number = NumberFormat('0.#');

/// A muscle as the result names it: `front_delt` → "front delt".
String _muscle(Muscle muscle) => muscle.code.replaceAll('_', ' ');

/// A score part's key as words: `aboveLevel` → "above level".
String _part(String key) => key
    .replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}')
    .trim();

/// A line under the rules choice: why "My changes" cannot run now, or why
/// the published rules run instead.
String? _sourceNote(GeneratorSimulatorState state) => switch (state) {
  GeneratorSimulatorState(source: RulesSource.draft, :final draftCheck) =>
    switch (draftCheck) {
      DraftCheck.checking => 'Checking…',
      DraftCheck.unchecked =>
        'Your changes could not be checked. Retry the check above.',
      _ => null,
    },
  GeneratorSimulatorState(fallback: DraftCheck.problems) =>
    'Your changes have problems, so the published rules run.',
  GeneratorSimulatorState(fallback: DraftCheck.unchanged) =>
    'There are no unpublished changes any more, so the published rules '
        'run.',
  _ => null,
};

/// What the simulator says about a failed run.
String _failureText(Failure failure) => switch (failure) {
  GenerationRefused(refusal: GenerationRefusal.noTemplate) =>
    'No program: no template of these rules fits these days, level and '
        'goal.',
  GenerationRefused(refusal: GenerationRefusal.noExercises) =>
    'No program: these answers leave a day without an exercise.',
  GenerationRefused(refusal: GenerationRefusal.noRules) =>
    'No program: no rules are published.',
  PermissionFailure() => 'Refused: this account has no current admin claim.',
  GeneratorRulesInvalidFailure(:final problems) =>
    'Refused: the server found ${problems.length} problem(s) in your '
        'changes.',
  GeneratorRulesUnavailableFailure() =>
    'The generateProgram function is not deployed to this project.',
  ValidationFailure(:final message) => 'Refused: $message',
  _ => failureMessage(failure),
};

/// The generator simulator (AG4): the answers on the left, the last run's
/// program on the right with why each exercise was picked. Runs the
/// published rules or, while they may be run, the unpublished changes.
class SimulatorTab extends StatefulWidget {
  const SimulatorTab({super.key});

  @override
  State<SimulatorTab> createState() => _SimulatorTabState();
}

class _SimulatorTabState extends State<SimulatorTab> {
  @override
  void initState() {
    super.initState();
    _offerRules(context.read<GeneratorRulesCubit>().state);
  }

  void _offerRules(GeneratorRulesState rules) =>
      context.read<GeneratorSimulatorCubit>().setRules(
        published: rules.loaded,
        draft: rules.hasChanges ? rules.draft : null,
        draftCheck: rules.draftCheck,
      );

  @override
  Widget build(BuildContext context) =>
      BlocListener<GeneratorRulesCubit, GeneratorRulesState>(
        listenWhen: (previous, state) =>
            previous.loaded != state.loaded ||
            previous.draft != state.draft ||
            previous.draftCheck != state.draftCheck,
        listener: (_, state) => _offerRules(state),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.md,
          children: [
            SizedBox(width: GeneratorSizes.answers, child: _Answers()),
            Expanded(child: _Result()),
          ],
        ),
      );
}

class _Answers extends StatelessWidget {
  const _Answers();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorSimulatorCubit>();
    final state = context.watch<GeneratorSimulatorCubit>().state;
    final label = Theme.of(context).textTheme.labelLarge;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            Text('Rules', style: label),
            if (state.sources.isNotEmpty)
              SegmentedButton<RulesSource>(
                showSelectedIcon: false,
                segments: [
                  for (final source in state.sources)
                    ButtonSegment(
                      value: source,
                      label: Text(switch (source) {
                        RulesSource.published =>
                          'Published v${state.published?.version}',
                        RulesSource.draft => 'My changes',
                      }),
                    ),
                ],
                selected: {?state.source},
                onSelectionChanged: (picked) =>
                    cubit.selectSource(picked.single),
              ),
            if (_sourceNote(state) case final note?) Hint(note),
            _Dropdown<Goal>(
              label: 'Goal',
              value: state.goal,
              options: {for (final goal in Goal.values) goal: codeLabel(goal)},
              onChanged: cubit.setGoal,
            ),
            _Dropdown<Level>(
              label: 'Level',
              value: state.level,
              options: {
                for (final level in Level.values) level: codeLabel(level),
              },
              onChanged: cubit.setLevel,
            ),
            Row(
              spacing: Gap.sm,
              children: [
                Expanded(
                  child: _Dropdown<int>(
                    label: 'Days',
                    value: state.daysPerWeek,
                    options: {
                      for (
                        var days = GeneratorSimulatorState.minDays;
                        days <= GeneratorSimulatorState.maxDays;
                        days++
                      )
                        days: '$days',
                    },
                    onChanged: cubit.setDays,
                  ),
                ),
                Expanded(
                  child: _Dropdown<int>(
                    label: 'Session',
                    value: state.sessionMinutes,
                    options: {
                      for (final minutes in state.sessionOptions)
                        minutes: '$minutes min',
                    },
                    onChanged: cubit.setSessionMinutes,
                  ),
                ),
              ],
            ),
            _Dropdown<EquipmentProfile>(
              label: 'Equipment',
              value: state.equipment,
              options: {
                for (final preset in EquipmentProfile.values)
                  preset: codeLabel(preset),
              },
              onChanged: cubit.setEquipment,
            ),
            _Dropdown<EquipmentStyle>(
              label: 'Style',
              value: state.equipmentStyle,
              options: {
                for (final style in EquipmentStyle.values)
                  style: style == EquipmentStyle.any
                      ? 'No preference'
                      : codeLabel(style),
              },
              onChanged: cubit.setEquipmentStyle,
            ),
            _MultiPicker<FocusArea>(
              label: 'Focus',
              values: FocusArea.values,
              selected: state.focus,
              enabled: (area) =>
                  state.focus.contains(area) ||
                  state.focus.length < state.maxFocus,
              onToggle: cubit.toggleFocus,
            ),
            _MultiPicker<FocusArea>(
              label: 'Leave out',
              values: FocusArea.values,
              selected: state.skip,
              enabled: (area) =>
                  state.skip.contains(area) ||
                  (!state.focus.contains(area) &&
                      state.skip.length < state.maxSkip),
              onToggle: cubit.toggleSkip,
            ),
            _MultiPicker<SensitiveArea>(
              label: 'Sensitive',
              values: SensitiveArea.values,
              selected: state.sensitive,
              enabled: (_) => true,
              onToggle: cubit.toggleSensitive,
            ),
            _Dropdown<String?>(
              label: 'Split',
              value: state.split,
              options: {
                null: 'Let the rules choose',
                for (final split in state.splits)
                  '${split['id']}': splitName(split),
              },
              onChanged: cubit.setSplit,
            ),
            TextFormField(
              initialValue: '${state.seed}',
              decoration: const InputDecoration(labelText: 'Seed'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (text) => cubit.setSeed(int.tryParse(text) ?? 0),
            ),
            FilledButton(
              onPressed: state.canGenerate ? cubit.generate : null,
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of [options] (value → label) in a menu.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // A value the cubit changes on its own (the rules changed) is shown.
      key: ValueKey((label, value, Object.hashAll(options.keys))),
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final MapEntry(key: value, value: text) in options.entries)
          DropdownMenuItem(value: value, child: Text(text)),
      ],
      onChanged: (picked) {
        if (picked is T) onChanged(picked);
      },
    );
  }
}

/// Some of [values], picked in a menu of tick boxes; [enabled] says which
/// may be ticked now.
class _MultiPicker<T extends Coded> extends StatelessWidget {
  const _MultiPicker({
    required this.label,
    required this.values,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final String label;
  final List<T> values;
  final Set<T> selected;
  final bool Function(T value) enabled;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final value in values)
          CheckboxMenuButton(
            value: selected.contains(value),
            closeOnActivate: false,
            onChanged: enabled(value) ? (_) => onToggle(value) : null,
            child: Text(codeLabel(value)),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            selected.isEmpty
                ? 'None'
                : codeLabels([
                    for (final value in values)
                      if (selected.contains(value)) value,
                  ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GeneratorSimulatorCubit>().state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: switch ((state.status, state.run, state.failure)) {
          (SimulationStatus.running, _, _) => const Center(
            child: CircularProgressIndicator(),
          ),
          (_, final run?, _) => _Program(run),
          (_, _, final failure?) => ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_failureText(failure)),
          ),
          _ => const Hint(
            'Pick the answers and press Generate to see the program and why '
            'each exercise was picked.',
          ),
        },
      ),
    );
  }
}

/// A run's program: the heading, a tab per day, the day's table and the
/// weekly sets.
class _Program extends StatelessWidget {
  const _Program(this.run);

  final SimulationRun run;

  @override
  Widget build(BuildContext context) {
    final simulation = run.simulation;
    final program = simulation.program;
    final muted = ForgeStyle.of(context).colors.inkMuted;
    // Set when the server's cached published rules were not the loaded ones.
    final loadedVersion = context.select(
      (GeneratorSimulatorCubit cubit) =>
          cubit.state.runVersionDiffers ? cubit.state.published?.version : null,
    );
    final uncovered = [
      for (final muscle in Muscle.values)
        if (program.uncovered.contains(muscle)) _muscle(muscle),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        Wrap(
          spacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              program.splitName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              [
                if (run.request.rules == null)
                  'Published v${simulation.rulesVersion}'
                else
                  'My changes',
                'template ${simulation.template}',
                '${program.lengthWeeks} weeks',
                if (uncovered.isEmpty)
                  'nothing uncovered'
                else
                  'uncovered: ${uncovered.join(', ')}',
              ].join(' · '),
              style: TextStyle(color: muted),
            ),
          ],
        ),
        if (loadedVersion != null)
          Text(
            'Built with version ${simulation.rulesVersion}; version '
            '$loadedVersion is published, try again in a minute',
          ),
        _DayTabs(key: ValueKey(run), run: run),
        _DayTable(run),
        _WeeklySets(run, targets: loadedVersion == null),
      ],
    );
  }
}

/// The week's sets per targeted muscle as bars, two columns, each with a
/// tick at that muscle's own target and drawn quieter while under it; then
/// the other muscles the week trains on one line. Without [targets]
/// (unknown rules) every trained muscle is a bar with no tick.
class _WeeklySets extends StatelessWidget {
  const _WeeklySets(this.run, {required this.targets});

  final SimulationRun run;
  final bool targets;

  static const double _barHeight = 10;
  static const double _tickHeight = 18;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final small = text.bodySmall!.copyWith(color: colors.inkMuted);
    final simulation = run.simulation;
    double sets(Muscle muscle) => simulation.weeklySets[muscle] ?? 0;
    final barred = [
      for (final muscle in Muscle.values)
        if (targets
            ? simulation.program.targeted.contains(muscle)
            : sets(muscle) > 0)
          muscle,
    ];
    final aims = targets
        ? weeklyTargets(run.rules, run.request.answers, barred)
        : const <Muscle, double>{};
    final others = [
      for (final muscle in Muscle.values)
        if (!barred.contains(muscle) && sets(muscle) > 0) muscle,
    ];
    final scale = [
      1.0,
      for (final muscle in barred) ...[sets(muscle), aims[muscle] ?? 0],
    ].reduce((a, b) => a > b ? a : b);

    Widget bar(Muscle muscle) {
      final aim = aims[muscle];
      final under = aim != null && sets(muscle) < aim;
      return Row(
        spacing: Gap.sm,
        children: [
          SizedBox(
            width: 96,
            child: Text(_muscle(muscle), overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return SizedBox(
                  height: _tickHeight,
                  child: Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      Container(
                        height: _barHeight,
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: BorderRadius.circular(_barHeight / 2),
                        ),
                      ),
                      Container(
                        width: width * sets(muscle) / scale,
                        height: _barHeight,
                        decoration: BoxDecoration(
                          color: under ? colors.lineStrong : colors.ink,
                          borderRadius: BorderRadius.circular(_barHeight / 2),
                        ),
                      ),
                      if (aim != null)
                        PositionedDirectional(
                          start: (width * aim / scale - 1).clamp(0, width - 2),
                          child: Container(
                            width: 2,
                            height: _tickHeight,
                            color: colors.success,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              aim == null
                  ? _number.format(sets(muscle))
                  : '${_number.format(sets(muscle))} / ${_number.format(aim)}',
              textAlign: TextAlign.end,
              style: style.data.copyWith(color: colors.inkMuted),
            ),
          ),
        ],
      );
    }

    final half = (barred.length / 2).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        const Divider(height: Gap.md),
        Wrap(
          spacing: Gap.md,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text('Weekly sets', style: text.titleSmall),
            if (targets)
              Text(
                'bar: sets in the week · green tick: the muscle\'s target · '
                'grey: under target',
                style: small,
              ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.lg,
          children: [
            for (final column in [barred.take(half), barred.skip(half)])
              Expanded(
                child: Column(
                  spacing: Gap.xs,
                  children: [for (final muscle in column) bar(muscle)],
                ),
              ),
          ],
        ),
        if (others.isNotEmpty)
          Text(
            'Also trained: ${[for (final muscle in others) '${_muscle(muscle)} ${_number.format(sets(muscle))}'].join(' · ')}',
            style: small,
          ),
      ],
    );
  }
}

/// "Upper A · 53 min" per day, as the engine counts it ([dayMinutes]).
class _DayTabs extends StatefulWidget {
  const _DayTabs({super.key, required this.run});

  final SimulationRun run;

  List<ProgramDay> get days => run.simulation.program.days;

  @override
  State<_DayTabs> createState() => _DayTabsState();
}

class _DayTabsState extends State<_DayTabs>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: widget.days.length,
    vsync: this,
    initialIndex: context.read<GeneratorSimulatorCubit>().state.day.clamp(
      0,
      widget.days.length - 1,
    ),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      onTap: context.read<GeneratorSimulatorCubit>().selectDay,
      tabs: [
        for (final day in widget.days)
          Tab(
            text:
                '${day.name} · '
                '${dayMinutes(day, widget.run.rules)} min',
          ),
      ],
    );
  }
}

/// The cells of a table row: the exercise wider than the slot, the
/// numbers narrowest.
Widget _row(List<Widget> cells) => Padding(
  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
  child: Row(
    spacing: Gap.sm,
    children: [
      for (final (i, cell) in cells.indexed)
        Expanded(
          flex: switch (i) {
            0 => 3,
            1 => 2,
            _ => 1,
          },
          child: cell,
        ),
    ],
  ),
);

/// The open day's exercises; a scored row opens to its score parts and
/// the next candidates.
class _DayTable extends StatelessWidget {
  const _DayTable(this.run);

  final SimulationRun run;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GeneratorSimulatorCubit>().state;
    final days = run.simulation.program.days;
    final d = state.day.clamp(0, days.length - 1);
    final reasons = run.simulation.trace.elementAtOrNull(d) ?? const [];
    final heading = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row([
          for (final title in [
            'Exercise',
            'Slot',
            'Sets × reps',
            'Rest',
            'Score',
          ])
            Text(title, style: heading),
        ]),
        const Divider(height: 1),
        for (final (i, item) in days[d].items.indexed) ...[
          _ItemRow(
            index: i,
            item: item,
            reason: reasons.elementAtOrNull(i),
            open: state.openRow == i,
            names: state.names,
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.item,
    required this.reason,
    required this.open,
    required this.names,
  });

  final int index;
  final ProgramItem item;
  final PickReason? reason;
  final bool open;
  final Map<String, String> names;

  String _name(String id) => names[id] ?? id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = this.reason;
    final total = reason?.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: total == null
              ? null
              : () => context.read<GeneratorSimulatorCubit>().toggleRow(index),
          child: _row([
            Text(
              _name(item.exerciseId),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(reason == null ? '' : _slot(reason)),
            Text(_dose(item)),
            Text('${item.restS} s'),
            Row(
              spacing: Gap.xs,
              children: [
                Text(total?.toStringAsFixed(1) ?? '—'),
                if (total != null)
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    size: Gap.md,
                  ),
              ],
            ),
          ]),
        ),
        if (open && reason != null)
          ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Text(
                _why(reason, _name),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Primary · 1", plus how it was picked when not by its slot alone.
String _slot(PickReason reason) => [
  codeLabel(reason.role),
  '${reason.priority}',
  if (reason.source != PickSource.slot) reason.source.name,
].join(' · ');

/// "4 × 6–10", "3 × 8" or a hold, "3 × 30 s".
String _dose(ProgramItem item) => switch (item) {
  ProgramItem(:final durationS?) => '${item.sets} × $durationS s',
  ProgramItem(:final repMin, :final repMax) when repMin == repMax =>
    '${item.sets} × $repMin',
  ProgramItem(:final repMin, :final repMax) => '${item.sets} × $repMin–$repMax',
};

/// "tier 30 · equipment 12 · … — next: Box Squat 44.1 · …".
String _why(PickReason reason, String Function(String id) name) {
  final parts = [
    for (final MapEntry(:key, :value) in reason.score.entries)
      '${_part(key)} ${_number.format(value)}',
  ].join(' · ');
  final next = [
    for (final other in reason.others)
      '${name(other.exerciseId)} ${other.score.toStringAsFixed(1)}',
  ].join(' · ');
  return [parts, if (next.isNotEmpty) 'next: $next'].join(' — ');
}
