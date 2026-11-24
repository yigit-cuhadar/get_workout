import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_form.dart';
import '../domain/announcement.dart';
import 'announcement_text.dart';

/// Asks before [draft] goes out, naming its audience and time and showing
/// its text. One sent now cannot be recalled, so Send stays off until "I
/// understand it cannot be recalled" is ticked; a scheduled one can be
/// cancelled until it goes and needs no tick. Pops true to send.
class SendConfirmDialog extends StatefulWidget {
  const SendConfirmDialog({super.key, required this.draft});

  /// The trimmed text as it is sent.
  final AnnouncementDraft draft;

  @override
  State<SendConfirmDialog> createState() => _SendConfirmDialogState();
}

class _SendConfirmDialogState extends State<SendConfirmDialog> {
  bool _understood = false;

  void _toggle() => setState(() => _understood = !_understood);

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final draft = widget.draft;
    final at = draft.scheduleAt;
    final who = audiencePhrase(draft.audience);
    return AlertDialog(
      title: Text(
        at == null ? 'Send to $who now?' : 'Send to $who ${scheduleLabel(at)}?',
      ),
      content: SizedBox(
        width: maxFormWidth / 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md,
          children: [
            Text(
              at == null
                  ? 'It notifies $who of the "${draft.locale}" app language '
                        'who allowed notifications, right away. A sent '
                        'announcement cannot be recalled or edited.'
                  : 'It notifies $who of the "${draft.locale}" app language '
                        'who allowed notifications then. You can cancel it in '
                        'the list until then; once sent it cannot be recalled.',
              style: text.bodyMedium?.copyWith(color: style.colors.inkMuted),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: style.colors.line),
                borderRadius: BorderRadius.circular(style.radii.md),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.xs,
                  children: [
                    Text(draft.title, style: text.titleSmall),
                    Text(draft.body, style: text.bodyMedium),
                  ],
                ),
              ),
            ),
            if (at == null)
              MergeSemantics(
                child: InkWell(
                  onTap: _toggle,
                  child: Row(
                    spacing: Gap.sm,
                    children: [
                      ForgeCheckbox(
                        value: _understood,
                        onChanged: (_) => _toggle(),
                      ),
                      const Expanded(
                        child: Text('I understand it cannot be recalled'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        ForgeButton(
          label: 'Cancel',
          variant: ForgeButtonVariant.outline,
          onPressed: () => Navigator.pop(context, false),
        ),
        ForgeButton(
          label: at == null ? 'Send now' : 'Schedule',
          onPressed: at != null || _understood
              ? () => Navigator.pop(context, true)
              : null,
        ),
      ],
    );
  }
}
