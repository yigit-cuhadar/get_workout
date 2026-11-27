import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/first_weekday.dart';
import '../domain/calendar_date.dart';
import '../domain/program_schedule.dart';
import 'program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/once_tip.dart';

/// Asks which program day each training weekday does, starting
/// from [initial]; [dayNames] are the program's days by index. Returns the
/// schedule, or null when cancelled.
Future<Map<int, int>?> showTrainingDays(
  BuildContext context, {
  required List<String> dayNames,
  required Map<int, int> initial,
  required String confirmLabel,
}) => showForgeBottomSheet<Map<int, int>>(
  context: context,
  builder: (context) => TrainingDaysSheet(
    dayNames: dayNames,
    initial: initial,
    firstWeekday: context.watchFirstWeekday(),
    confirmLabel: confirmLabel,
  ),
);

/// Which weekdays each program day is done on, in a week starting on ISO
/// weekday [firstWeekday] (SD3 B, SD4 C). Simple picks exactly one weekday
/// per day, the days going onto them in week order; Custom (SD2 E) has a
/// card per day, titled with its full name, over the seven weekdays, so a
/// day may be done on several. A weekday holds one day, so picking it for
/// a day takes it from any other. Under the weekdays, how many days a week
/// and which weekdays rest.
class TrainingDaysSheet extends StatefulWidget {
  const TrainingDaysSheet({
    super.key,
    required this.dayNames,
    required this.initial,
    required this.firstWeekday,
    required this.confirmLabel,
  });

  final List<String> dayNames;
  final Map<int, int> initial;
  final int firstWeekday;
  final String confirmLabel;

  @override
  State<TrainingDaysSheet> createState() => _TrainingDaysSheetState();
}

class _TrainingDaysSheetState extends State<TrainingDaysSheet> {
  late final int _dayCount = widget.dayNames.length;
  late final List<int> _week = weekdaysFrom(widget.firstWeekday);

  // A program that lost days keeps its weekdays on days it still has.
  late Map<int, int> _schedule = {
    for (final MapEntry(:key, :value) in widget.initial.entries)
      key: value % _dayCount,
  };

  // A new program, with no schedule, starts Simple too.
  late bool _simple =
      _schedule.isEmpty ||
      ProgramSchedule.isInWeekOrder(_schedule, _dayCount, _week);

  /// The weekdays picked in Simple.
  late Set<int> _picked = _simple ? {..._schedule.keys} : {};

  /// Whether the weekdays were picked anew since Simple was shown; if not,
  /// Custom comes back as it was.
  bool _repicked = false;

  void _toggle(int weekday, int dayIndex) => setState(() {
    if (_schedule[weekday] == dayIndex) {
      _schedule.remove(weekday);
    } else {
      _schedule[weekday] = dayIndex;
    }
  });

  // At the day count, an unpicked weekday does nothing.
  void _pick(int weekday) {
    if (!_picked.contains(weekday) && _picked.length == _dayCount) return;
    setState(() {
      if (!_picked.remove(weekday)) _picked.add(weekday);
      _repicked = true;
    });
  }

  void _switch(bool simple) => setState(() {
    if (simple == _simple) return;
    _simple = simple;
    if (simple) {
      _picked = ProgramSchedule.hasEachDayOnce(_schedule, _dayCount)
          ? {..._schedule.keys}
          : {};
    } else if (_repicked) {
      _schedule = ProgramSchedule.inWeekOrder(_picked, _week);
    }
    _repicked = false;
  });

  /// What Save returns, or null while it cannot save.
  Map<int, int>? get _result {
    if (!_simple) return _schedule.isEmpty ? null : {..._schedule};
    if (_picked.length != _dayCount) return null;
    return ProgramSchedule.inWeekOrder(_picked, _week);
  }

  String _summary(AppLocalizations l10n, Set<int> training) {
    final count = l10n.programTrainingDaysCount(training.length);
    final rest = [
      for (final weekday in _week)
        if (!training.contains(weekday)) l10n.weekdayShort(weekday),
    ];
    if (rest.isEmpty) return count;
    final restList = rest.length == 1
        ? rest.single
        : l10n.programTrainingDaysAnd(
            rest.take(rest.length - 1).join(l10n.listSeparator),
            rest.last,
          );
    return '$count · ${l10n.programTrainingDaysRest(restList)}';
  }

  Widget _weekdays({
    required bool Function(int weekday) selected,
    required void Function(int weekday) onPressed,
  }) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: Gap.xs,
    runSpacing: Gap.xs,
    children: [
      for (final weekday in _week)
        _WeekdayChip(
          weekday: weekday,
          selected: selected(weekday),
          onPressed: () => onPressed(weekday),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    final result = _result;
    final training = _simple ? _picked : _schedule.keys.toSet();
    return ForgeBottomSheet(
      title: l10n.programTrainingDaysTitle,
      action: Row(
        spacing: Gap.sm,
        children: [
          Expanded(
            child: ForgeButton(
              label: l10n.cancel,
              variant: ForgeButtonVariant.secondary,
              size: ForgeButtonSize.large,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: ForgeButton(
              label: widget.confirmLabel,
              size: ForgeButtonSize.large,
              onPressed: result == null
                  ? null
                  : () => Navigator.pop(context, result),
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          ForgeSegmentedControl<bool>(
            segments: [
              ForgeSegment(value: true, label: l10n.programTrainingDaysSimple),
              ForgeSegment(value: false, label: l10n.programTrainingDaysCustom),
            ],
            selected: _simple,
            onChanged: _switch,
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Gap.md,
                children: [
                  // How weekdays are picked, once.
                  OnceTip(
                    Tip.trainingDays,
                    _simple
                        ? l10n.programTrainingDaysSimpleHint(_dayCount)
                        : l10n.programTrainingDaysHint,
                  ),
                  if (_simple) ...[
                    _weekdays(selected: _picked.contains, onPressed: _pick),
                  ] else ...[
                    for (final (dayIndex, name) in widget.dayNames.indexed)
                      SectionCard.plain(
                        title: name,
                        child: _weekdays(
                          selected: (weekday) => _schedule[weekday] == dayIndex,
                          onPressed: (weekday) => _toggle(weekday, dayIndex),
                        ),
                      ),
                  ],
                  if (training.isNotEmpty)
                    Text(_summary(l10n, training), style: muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A weekday's two letters, read out as its full name.
class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.weekday,
    required this.selected,
    required this.onPressed,
  });

  final int weekday;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.weekdayLong(weekday),
      button: true,
      selected: selected,
      onTap: onPressed,
      excludeSemantics: true,
      child: ForgeChip(
        label: l10n.weekdayTwoLetter('$weekday'),
        selected: selected,
        showCheck: false,
        onPressed: onPressed,
      ),
    );
  }
}
