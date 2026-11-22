import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/program.dart';
import '../domain/program_validation.dart';
import 'program_text.dart';

/// One program item as [ItemTargetsSheet] edits it; each change applies at
/// once.
abstract interface class ItemTargets {
  /// The item as it is now.
  ProgramItem get item;
  WeightUnit get weightUnit;

  /// The item's issues as it changes, rebuilding [context] on a change.
  Set<ItemIssue> watchIssues(BuildContext context);
  void setSets(String text);
  void setRepMin(String text);
  void setRepMax(String text);

  /// In seconds.
  void setDuration(String text);
  void setRest(int seconds);

  /// In [weightUnit]; blank removes the target.
  void setTarget(String text);
}

/// Sets, reps or duration, rest and target of one item; every change
/// applies at once. The program builder's and the generator preview's.
class ItemTargetsSheet extends StatefulWidget {
  const ItemTargetsSheet({
    super.key,
    required this.title,
    required this.durationBased,
    required this.logsWeight,
    required this.targets,
  });

  final String title;
  final bool durationBased;
  final bool logsWeight;
  final ItemTargets targets;

  @override
  State<ItemTargetsSheet> createState() => _ItemTargetsSheetState();
}

class _ItemTargetsSheetState extends State<ItemTargetsSheet> {
  late final ItemTargets _targets = widget.targets;
  late final ProgramItem _item = _targets.item;
  late final _sets = _controller('${_item.sets}');
  late final _repMin = _controller(_item.repMin?.toString() ?? '');
  late final _repMax = _controller(_item.repMax?.toString() ?? '');
  late final _duration = _controller(_item.durationS?.toString() ?? '');
  late final _target = _controller(_targetText());
  late int _restS = _item.restS;
  final _controllers = <TextEditingController>[];

  TextEditingController _controller(String text) {
    final controller = TextEditingController(text: text);
    _controllers.add(controller);
    return controller;
  }

  String _targetText() {
    final kg = _item.targetKg;
    if (kg == null) return '';
    final value = _targets.weightUnit.shownFromKg(kg);
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickRest() => showForgeDurationWheel(
    context: context,
    wheel: ForgeDurationWheel.minutesSeconds(
      label: AppLocalizations.of(context).builderRest,
      initial: Duration(seconds: _restS),
      max: const Duration(seconds: ProgramLimits.maxRestS),
      step: const Duration(seconds: 15),
      onChanged: (rest) {
        setState(() => _restS = rest.inSeconds);
        _targets.setRest(rest.inSeconds);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    final issues = _targets.watchIssues(context);
    String? error(Set<ItemIssue> of) =>
        issues.where(of.contains).map(l10n.itemIssueText).firstOrNull;
    final repsError = error({
      ItemIssue.repsMissing,
      ItemIssue.repsOutOfRange,
      ItemIssue.repRangeInverted,
    });
    return ForgeBottomSheet(
      title: widget.title,
      action: ForgeButton(
        label: l10n.libraryDone,
        onPressed: () => Navigator.pop(context),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md,
          children: [
            _NumberField(
              controller: _sets,
              label: l10n.programSets,
              error: error({ItemIssue.setsOutOfRange}),
              onChanged: _targets.setSets,
            ),
            if (widget.durationBased)
              _NumberField(
                controller: _duration,
                label: l10n.programDurationSeconds,
                error: error({
                  ItemIssue.durationMissing,
                  ItemIssue.durationOutOfRange,
                }),
                onChanged: _targets.setDuration,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.sm,
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _repMin,
                      label: l10n.programRepMin,
                      error: repsError,
                      onChanged: _targets.setRepMin,
                    ),
                  ),
                  Expanded(
                    child: _NumberField(
                      controller: _repMax,
                      label: l10n.programRepMax,
                      error: repsError == null ? null : '',
                      onChanged: _targets.setRepMax,
                    ),
                  ),
                ],
              ),
            ForgeTextField.tapOnly(
              label: l10n.builderRest,
              value: l10n.restClock(_restS),
              onTap: _pickRest,
            ),
            if (widget.logsWeight)
              _NumberField(
                controller: _target,
                label: l10n.programTarget(
                  l10n.weightUnitLabel(_targets.weightUnit),
                ),
                error: error({ItemIssue.targetOutOfRange}),
                decimal: true,
                onChanged: _targets.setTarget,
              ),
            if (error({ItemIssue.wrongTarget}) case final text?)
              Text(
                text,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: colors.danger),
              ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.error,
    required this.onChanged,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final ValueChanged<String> onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) => ForgeTextField(
    label: label,
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [
      decimal
          ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
          : FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(decimal ? 7 : 4),
    ],
    errorText: error,
    onChanged: onChanged,
  );
}
