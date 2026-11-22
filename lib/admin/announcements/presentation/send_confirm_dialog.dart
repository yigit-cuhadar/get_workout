import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_form.dart';
import '../domain/announcement.dart';

/// Asks before [draft] goes out, showing its text; Send to everyone stays
/// off until "I understand it cannot be recalled" is ticked. Pops true to
/// send.
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
    return AlertDialog(
      title: const Text('Send this announcement to every user?'),
      content: SizedBox(
        width: maxFormWidth / 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md,
          children: [
            Text(
              'It notifies every user of the "${draft.locale}" app language '
              'who allowed notifications, right away. A sent announcement '
              'cannot be recalled or edited.',
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
          label: 'Send to everyone',
          onPressed: _understood ? () => Navigator.pop(context, true) : null,
        ),
      ],
    );
  }
}
