import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/first_weekday.dart';
import '../domain/calendar_date.dart';
import 'program_text.dart';

/// Asks for exactly [count] training weekdays, starting from [initial].
/// Returns them ascending, or null when cancelled.
Future<List<int>?> showWeekdayDialog(
  BuildContext context, {
  required int count,
  required List<int> initial,
  required String confirmLabel,
}) => showForgeDialog<List<int>>(
  context: context,
  builder: (_) => _WeekdayDialog(
    count: count,
    initial: initial,
    confirmLabel: confirmLabel,
  ),
);

class _WeekdayDialog extends StatefulWidget {
  const _WeekdayDialog({
    required this.count,
    required this.initial,
    required this.confirmLabel,
  });

  final int count;
  final List<int> initial;
  final String confirmLabel;

  @override
  State<_WeekdayDialog> createState() => _WeekdayDialogState();
}

class _WeekdayDialogState extends State<_WeekdayDialog> {
  late final Set<int> _selected = {...widget.initial};

  void _toggle(int weekday) => setState(() {
    if (!_selected.remove(weekday)) _selected.add(weekday);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final complete = _selected.length == widget.count;
    return ForgeDialog(
      title: l10n.programPickDays(widget.count),
      message: l10n.programPickDaysMessage,
      field: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final weekday in weekdaysFrom(context.watchFirstWeekday()))
            ForgeChip(
              label: l10n.weekdayShort(weekday),
              selected: _selected.contains(weekday),
              showCheck: false,
              // A full choice takes no more days until one is removed.
              onPressed:
                  _selected.contains(weekday) || _selected.length < widget.count
                  ? () => _toggle(weekday)
                  : () {},
            ),
        ],
      ),
      action: ForgeButton(
        label: widget.confirmLabel,
        onPressed: complete
            ? () => Navigator.pop(context, _selected.toList()..sort())
            : null,
      ),
      cancel: ForgeButton(
        label: l10n.cancel,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}
