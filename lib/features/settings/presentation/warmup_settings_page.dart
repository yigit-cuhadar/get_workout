import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';

extension WarmupText on AppLocalizations {
  String warmupSchemeLabel(WarmupScheme scheme) => switch (scheme) {
    WarmupScheme.off => warmupSchemeOff,
    WarmupScheme.light => warmupSchemeLight,
    WarmupScheme.standard => warmupSchemeStandard,
    WarmupScheme.full => warmupSchemeFull,
    WarmupScheme.custom => warmupSchemeCustom,
  };

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
}

/// The automatic warm-up sets: a scheme (a preset, or custom sets each
/// edited, removed or added) and which exercises get them. Every change
/// applies at once. Needs [SettingsCubit] above it.
class WarmupSettingsPage extends StatelessWidget {
  const WarmupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<SettingsCubit>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAutoWarmups)),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          final settings = state.settings;
          final warmups = settings.warmups;
          void set(WarmupSettings changed) {
            cubit.update(settings.copyWith(warmups: changed));
            // Its tip has nothing left to tell.
            cubit.tipSeen(Tip.autoWarmups);
          }

          void setCustom(List<WarmupStep> custom) =>
              set(warmups.copyWith(custom: custom));
          final custom = warmups.custom;
          return ListView(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Text(l10n.warmupIntro),
              ),
              ListTile(
                dense: true,
                title: Text(
                  l10n.warmupSchemeTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              RadioGroup<WarmupScheme>(
                groupValue: warmups.scheme,
                onChanged: (scheme) => set(
                  scheme == WarmupScheme.custom
                      ? warmups.toCustom()
                      : warmups.copyWith(scheme: scheme),
                ),
                child: Column(
                  children: [
                    for (final scheme in WarmupScheme.values)
                      RadioListTile<WarmupScheme>(
                        value: scheme,
                        title: Text(l10n.warmupSchemeLabel(scheme)),
                        subtitle: Text(switch (scheme) {
                          WarmupScheme.off => l10n.warmupSchemeOffHint,
                          WarmupScheme.custom when custom.isNotEmpty =>
                            l10n.warmupStepsText(custom),
                          WarmupScheme.custom => l10n.warmupSchemeCustomHint,
                          _ => l10n.warmupStepsText(scheme.presetSteps),
                        }),
                      ),
                  ],
                ),
              ),
              if (warmups.scheme == WarmupScheme.custom) ...[
                for (final (i, step) in custom.indexed)
                  _StepRow(
                    // Rows are made anew when one is added or removed.
                    key: ValueKey((custom.length, i)),
                    step: step,
                    onChanged: (changed) => setCustom([
                      for (final (j, other) in custom.indexed)
                        j == i ? changed : other,
                    ]),
                    onRemove: custom.length > 1
                        ? () => setCustom([...custom]..removeAt(i))
                        : null,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l10n.warmupAddSet),
                      onPressed: custom.length >= WarmupLimits.maxSets
                          ? null
                          : () =>
                                setCustom([...custom, nextWarmupStep(custom)]),
                    ),
                  ),
                ),
              ],
              ListTile(
                dense: true,
                title: Text(
                  l10n.warmupScopeTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              RadioGroup<WarmupScope>(
                groupValue: warmups.scope,
                onChanged: (scope) => set(warmups.copyWith(scope: scope)),
                child: Column(
                  children: [
                    RadioListTile<WarmupScope>(
                      value: WarmupScope.every,
                      title: Text(l10n.warmupScopeEvery),
                    ),
                    RadioListTile<WarmupScope>(
                      value: WarmupScope.firstPerMuscle,
                      title: Text(l10n.warmupScopeFirst),
                      subtitle: Text(l10n.warmupScopeFirstHint),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One custom warm-up set: its percentage and reps, each checked against
/// [WarmupLimits] as typed; [onChanged] gets it only while valid.
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
    Widget field(
      TextEditingController controller,
      String label,
      WarmupStepIssue issue,
      int min,
      int max,
    ) => TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      decoration: InputDecoration(
        labelText: label,
        errorText: _issues.contains(issue)
            ? l10n.calcOutOfRange('$min', '$max')
            : null,
      ),
      onChanged: (_) => _changed(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.sm,
        children: [
          Expanded(
            child: field(
              _percent,
              l10n.warmupPercent,
              WarmupStepIssue.percentOutOfRange,
              WarmupLimits.minPercent,
              WarmupLimits.maxPercent,
            ),
          ),
          Expanded(
            child: field(
              _reps,
              l10n.warmupReps,
              WarmupStepIssue.repsOutOfRange,
              WarmupLimits.minReps,
              WarmupLimits.maxReps,
            ),
          ),
          IconButton(
            tooltip: l10n.warmupRemoveSet,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
