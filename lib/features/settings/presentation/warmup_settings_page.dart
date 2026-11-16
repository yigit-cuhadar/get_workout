import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../workout/domain/warmups.dart';
import '../../workout/presentation/widgets/set_bubble.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';

/// One set of the example a preset scheme shows: its weight in the user's
/// unit, its reps and the share of the working weight it is.
typedef WarmupExampleSet = ({String weight, int reps, int percent});

extension WarmupText on AppLocalizations {
  String warmupSchemeLabel(WarmupScheme scheme) => switch (scheme) {
    WarmupScheme.off => warmupSchemeOff,
    WarmupScheme.light => warmupSchemeLight,
    WarmupScheme.standard => warmupSchemeStandard,
    WarmupScheme.full => warmupSchemeFull,
    WarmupScheme.custom => warmupSchemeCustom,
  };

  /// What [scheme] adds, after its name: `2 sets · default`, or the
  /// [custom] sets once there are some.
  String warmupSchemeValue(WarmupScheme scheme, List<WarmupStep> custom) {
    if (scheme == WarmupScheme.off) return warmupSchemeOffHint;
    if (scheme == WarmupScheme.custom) {
      return custom.isEmpty ? warmupSchemeCustomHint : warmupStepsText(custom);
    }
    final sets = warmupSets(scheme.presetSteps.length);
    return scheme == const WarmupSettings().scheme ? warmupDefault(sets) : sets;
  }

  /// `50 % × 8 · 75 % × 4`.
  String warmupStepsText(List<WarmupStep> steps) =>
      [for (final step in steps) warmupStep(step.percent, step.reps)]
          .join(' · ');

  String warmupScopeLabel(WarmupScope scope) => switch (scope) {
    WarmupScope.every => warmupScopeEvery,
    WarmupScope.firstPerMuscle => warmupScopeFirst,
  };

  /// `Standard · Every exercise`, or `Off`.
  String warmupSettingsSummary(WarmupSettings settings) =>
      settings.scheme == WarmupScheme.off
      ? warmupSchemeOff
      : warmupSummary(
          warmupSchemeLabel(settings.scheme),
          warmupScopeLabel(settings.scope),
        );

  /// The line under a custom set, naming only what is out of range; null
  /// when nothing is.
  String? warmupStepError(Set<WarmupStepIssue> issues) {
    final percent = issues.contains(WarmupStepIssue.percentOutOfRange);
    final reps = issues.contains(WarmupStepIssue.repsOutOfRange);
    return switch ((percent, reps)) {
      (true, true) => warmupBothError(
        WarmupLimits.minPercent,
        WarmupLimits.maxPercent,
        WarmupLimits.minReps,
        WarmupLimits.maxReps,
      ),
      (true, false) => warmupPercentError(
        WarmupLimits.minPercent,
        WarmupLimits.maxPercent,
      ),
      (false, true) => warmupRepsError(
        WarmupLimits.minReps,
        WarmupLimits.maxReps,
      ),
      (false, false) => null,
    };
  }

  /// The example of a preset [scheme]: `Standard · Bench Press at 80 kg`.
  String warmupExampleText(WarmupScheme scheme, WeightUnit unit) =>
      warmupExampleTitle(
        warmupSchemeLabel(scheme),
        _weight(warmupExampleWorking(unit)),
        unit == WeightUnit.kg ? unitKg : unitLb,
      );

  /// `40 kg × 8`.
  String warmupExampleSetText(WarmupExampleSet set, WeightUnit unit) =>
      warmupExampleSet(
        set.weight,
        unit == WeightUnit.kg ? unitKg : unitLb,
        set.reps,
      );
}

/// The working weight of the example: a round number in each unit.
double warmupExampleWorking(WeightUnit unit) => switch (unit) {
  WeightUnit.kg => 80,
  WeightUnit.lb => 175,
};

/// The warm-up sets [steps] give before the example's working weight in
/// [unit], each rounded as a workout rounds it.
List<WarmupExampleSet> warmupExample(List<WarmupStep> steps, WeightUnit unit) {
  final working = unit.toKg(warmupExampleWorking(unit));
  return [
    for (final (i, step) in steps.indexed)
      if (rampedWarmup(i, working, unit, steps) case final set?)
        (
          weight: _weight(unit.fromKg(set.weightKg)),
          reps: set.reps,
          percent: step.percent,
        ),
  ];
}

String _weight(double value) => NumberFormat('0.#').format(value);

/// The automatic warm-up sets: a scheme (a preset, whose example shows, or
/// custom sets each edited, removed or added) and which exercises get
/// them. Every change applies at once. Needs [SettingsCubit] above it.
class WarmupSettingsPage extends StatelessWidget {
  const WarmupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.warmupTitle),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          final settings = state.settings;
          final warmups = settings.warmups;
          void set(WarmupSettings changed) {
            cubit.update(settings.copyWith(warmups: changed));
            // Its tip has nothing left to tell.
            cubit.tipSeen(Tip.autoWarmups);
          }

          final scheme = warmups.scheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            children: [
              SettingsColumn(
                children: [
                  ListRowCard(
                    children: [
                      for (final option in WarmupScheme.values)
                        Semantics(
                          inMutuallyExclusiveGroup: true,
                          checked: option == scheme,
                          child: ListRow(
                            leading: RadioMark(selected: option == scheme),
                            title: l10n.warmupSchemeLabel(option),
                            value: l10n.warmupSchemeValue(
                              option,
                              warmups.custom,
                            ),
                            onTap: () => set(
                              option == WarmupScheme.custom
                                  ? warmups.toCustom()
                                  : warmups.copyWith(scheme: option),
                            ),
                          ),
                        ),
                    ],
                  ),
                  switch (scheme) {
                    WarmupScheme.off => null,
                    WarmupScheme.custom => _CustomSets(
                      steps: warmups.custom,
                      onChanged: (custom) =>
                          set(warmups.copyWith(custom: custom)),
                    ),
                    _ => _Example(scheme, settings.weightUnit),
                  },
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsHeader(l10n.warmupScopeTitle),
                      ForgeSegmentedControl<WarmupScope>(
                        segments: [
                          for (final scope in WarmupScope.values)
                            ForgeSegment(
                              value: scope,
                              label: l10n.warmupScopeLabel(scope),
                            ),
                        ],
                        selected: warmups.scope,
                        onChanged: (scope) =>
                            set(warmups.copyWith(scope: scope)),
                      ),
                    ],
                  ),
                ].nonNulls.toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A preset's sets on the example lift.
class _Example extends StatelessWidget {
  const _Example(this.scheme, this.unit);

  final WarmupScheme scheme;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    return SectionCard.plain(
      title: l10n.warmupExampleText(scheme, unit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          for (final set in warmupExample(scheme.presetSteps, unit))
            Row(
              spacing: Gap.sm,
              children: [
                _WarmupBubble(l10n),
                Expanded(
                  child: Text(
                    l10n.warmupExampleSetText(set, unit),
                    style: style.data.copyWith(
                      fontSize: 14,
                      color: style.colors.ink,
                    ),
                  ),
                ),
                Text(
                  l10n.warmupPercentOf(set.percent),
                  style: style.data.copyWith(
                    fontSize: 12,
                    color: style.colors.inkMuted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WarmupBubble extends StatelessWidget {
  const _WarmupBubble(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => SetBubble(
    label: l10n.workoutWarmupShort,
    semanticLabel: l10n.workoutWarmupBubble,
    onTap: null,
    warmup: true,
    small: true,
  );
}

/// The custom sets, each edited in its row, removed while another is left,
/// and added up to [WarmupLimits.maxSets].
class _CustomSets extends StatelessWidget {
  const _CustomSets({required this.steps, required this.onChanged});

  final List<WarmupStep> steps;
  final ValueChanged<List<WarmupStep>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.warmupCustomTitle,
      detail: l10n.warmupCustomDetail,
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.xs,
        children: [
          for (final (i, step) in steps.indexed)
            _StepRow(
              // Rows are made anew when one is added or removed.
              key: ValueKey((steps.length, i)),
              step: step,
              onChanged: (changed) => onChanged([
                for (final (j, other) in steps.indexed)
                  j == i ? changed : other,
              ]),
              onRemove: steps.length > 1
                  ? () => onChanged([...steps]..removeAt(i))
                  : null,
            ),
          ForgeButton(
            label: l10n.warmupAddSet,
            variant: ForgeButtonVariant.text,
            size: ForgeButtonSize.small,
            leadingIcon: ForgeIcons.add,
            onPressed: steps.length >= WarmupLimits.maxSets
                ? null
                : () => onChanged([...steps, nextWarmupStep(steps)]),
          ),
        ],
      ),
    );
  }
}

/// One custom warm-up set: its percentage and reps, each checked against
/// [WarmupLimits] as typed; [onChanged] gets it only while valid, and one
/// line under the row names what is out of range.
class _StepRow extends StatefulWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.onChanged,
    required this.onRemove,
  });

  final WarmupStep step;
  final ValueChanged<WarmupStep> onChanged;

  /// Null for the only set.
  final VoidCallback? onRemove;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  late final _percent = TextEditingController(text: '${widget.step.percent}');
  late final _reps = TextEditingController(text: '${widget.step.reps}');
  Set<WarmupStepIssue> _issues = const {};

  @override
  void dispose() {
    _percent.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _changed() {
    // Unreadable text is out of range.
    final step = WarmupStep(
      int.tryParse(_percent.text) ?? 0,
      int.tryParse(_reps.text) ?? 0,
    );
    final issues = validateWarmupStep(step);
    setState(() => _issues = issues);
    if (issues.isEmpty) widget.onChanged(step);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final unitStyle = Theme.of(context).textTheme.labelMedium!
        .copyWith(fontWeight: FontWeight.w400, color: colors.inkMuted);
    Widget field(TextEditingController controller, String label) => Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => ForgeNumberField.compact(
          label: label,
          width: constraints.maxWidth,
          controller: controller,
          onChanged: (_) => _changed(),
        ),
      ),
    );
    final error = l10n.warmupStepError(_issues);
    final remove = widget.onRemove;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.xs,
      children: [
        Row(
          spacing: Gap.sm,
          children: [
            _WarmupBubble(l10n),
            field(_percent, l10n.warmupPercent),
            Text(l10n.warmupPercentUnit, style: unitStyle),
            field(_reps, l10n.warmupReps),
            Text(l10n.warmupRepsUnit, style: unitStyle),
            Semantics(
              button: true,
              enabled: remove != null,
              label: l10n.warmupRemoveSet,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: remove,
                child: SizedBox.square(
                  dimension: ForgeNumberField.compactHeight,
                  child: Center(
                    child: ForgeIcon(
                      ForgeIcons.close,
                      size: 18,
                      color: remove == null
                          ? colors.lineStrong
                          : colors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            // Under the fields, past the bubble.
            padding: const EdgeInsetsDirectional.only(
              start: SetBubble.smallDiameter + Gap.sm,
            ),
            child: Text(
              error,
              style: Theme.of(context).textTheme.labelMedium!
                  .copyWith(fontWeight: FontWeight.w400, color: colors.danger),
            ),
          ),
      ],
    );
  }
}
