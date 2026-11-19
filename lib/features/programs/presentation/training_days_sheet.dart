import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/first_weekday.dart';
import '../domain/calendar_date.dart';
import 'program_text.dart';

/// Asks which program day each training weekday does (SD2 E), starting
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

/// A card per program day, titled with its full name, over the seven
/// weekdays in a week starting on ISO weekday [firstWeekday]; the picked
/// ones are the weekdays the day is done on. A weekday holds one day, so
/// picking it for a day takes it from any other. Under the cards, how many
/// days a week and which weekdays rest.
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
  // A program that lost days keeps its weekdays on days it still has.
  late final Map<int, int> _schedule = {
    for (final MapEntry(:key, :value) in widget.initial.entries)
      key: value % widget.dayNames.length,
  };
  late final List<int> _week = weekdaysFrom(widget.firstWeekday);

  void _toggle(int weekday, int dayIndex) => setState(() {
    if (_schedule[weekday] == dayIndex) {
      _schedule.remove(weekday);
    } else {
      _schedule[weekday] = dayIndex;
    }
  });

  String _summary(AppLocalizations l10n) {
    final count = l10n.programTrainingDaysCount(_schedule.length);
    final rest = [
      for (final weekday in _week)
        if (!_schedule.containsKey(weekday)) l10n.weekdayShort(weekday),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: ForgeStyle.of(context).colors.inkMuted);
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
              onPressed: _schedule.isEmpty
                  ? null
                  : () => Navigator.pop(context, {..._schedule}),
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md,
          children: [
            Text(l10n.programTrainingDaysHint, style: muted),
            for (final (dayIndex, name) in widget.dayNames.indexed)
              SectionCard.plain(
                title: name,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    for (final weekday in _week)
                      _WeekdayChip(
                        weekday: weekday,
                        selected: _schedule[weekday] == dayIndex,
                        onPressed: () => _toggle(weekday, dayIndex),
                      ),
                  ],
                ),
              ),
            if (_schedule.isNotEmpty) Text(_summary(l10n), style: muted),
          ],
        ),
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
