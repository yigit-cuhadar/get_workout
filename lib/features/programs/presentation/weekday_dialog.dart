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
}) => showDialog<List<int>>(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final complete = _selected.length == widget.count;
    return AlertDialog(
      title: Text(l10n.programPickDays(widget.count)),
      content: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.xs,
        children: [
          for (final weekday in weekdaysFrom(context.watchFirstWeekday()))
            FilterChip(
              label: Text(l10n.weekdayShort(weekday)),
              selected: _selected.contains(weekday),
              // A full choice takes no more days until one is removed.
              onSelected:
                  _selected.contains(weekday) || _selected.length < widget.count
                  ? (on) => setState(
                      () => on
                          ? _selected.add(weekday)
                          : _selected.remove(weekday),
                    )
                  : null,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: complete
              ? () => Navigator.pop(context, _selected.toList()..sort())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
