import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../features/exercises/domain/vocabulary.dart';
import 'admin_text.dart';

/// The bar at the foot of an editor of content with a status, always in
/// view: whether there are unsaved changes, and a button per way to save —
/// as it is, as draft, publish, retire. Publishing, and taking live content
/// back, ask first.
class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.noun,
    required this.liveEffect,
    required this.hiddenEffect,
    required this.stored,
    required this.dirty,
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onSaveAs,
  });

  /// What is edited, e.g. "exercise".
  final String noun;

  /// What publishing does for users, as a sentence.
  final String liveEffect;

  /// What leaving live does for users, as a sentence.
  final String hiddenEffect;

  /// The stored status; null when nothing is stored yet.
  final ExerciseStatus? stored;
  final bool dirty;
  final bool saving;

  /// Whether saving with a status (null: the current one) writes anything.
  final bool Function([ExerciseStatus? status]) canSave;
  final VoidCallback onSave;
  final ValueChanged<ExerciseStatus> onSaveAs;

  Future<void> _confirmThen(
    BuildContext context, {
    required String title,
    required String body,
    required String confirm,
    required VoidCallback action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) action();
  }

  @override
  Widget build(BuildContext context) {
    final stored = this.stored;
    VoidCallback? when(ExerciseStatus? status, VoidCallback action) =>
        saving || !canSave(status) ? null : action;
    void publish() => _confirmThen(
      context,
      title: 'Publish this $noun?',
      body: liveEffect,
      confirm: 'Publish',
      action: () => onSaveAs(ExerciseStatus.live),
    );
    void retire() => _confirmThen(
      context,
      title: 'Retire this $noun?',
      body: '$hiddenEffect It is kept, and can be published again.',
      confirm: 'Retire',
      action: () => onSaveAs(ExerciseStatus.retired),
    );
    void toDraft() => stored == ExerciseStatus.live
        ? _confirmThen(
            context,
            title: 'Move this $noun back to draft?',
            body: hiddenEffect,
            confirm: 'Move to draft',
            action: () => onSaveAs(ExerciseStatus.draft),
          )
        : onSaveAs(ExerciseStatus.draft);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          spacing: Gap.md,
          children: [
            Expanded(
              child: Text(
                saving
                    ? 'Saving…'
                    : dirty
                    ? 'Unsaved changes'
                    : 'No unsaved changes',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Gap.sm,
              children: [
                if (stored != ExerciseStatus.draft)
                  ForgeButton(
                    label: 'Save as draft',
                    variant: ForgeButtonVariant.outline,
                    onPressed: when(ExerciseStatus.draft, toDraft),
                  ),
                if (stored != ExerciseStatus.live)
                  ForgeButton(
                    label: 'Publish',
                    // With nothing stored, publishing is the main way.
                    variant: stored == null
                        ? ForgeButtonVariant.primary
                        : ForgeButtonVariant.secondary,
                    onPressed: when(ExerciseStatus.live, publish),
                  ),
                if (stored != null && stored != ExerciseStatus.retired)
                  ForgeButton(
                    label: 'Retire',
                    variant: ForgeButtonVariant.danger,
                    onPressed: when(ExerciseStatus.retired, retire),
                  ),
                if (stored != null)
                  ForgeButton(
                    label: 'Save (stays ${codeLabel(stored)})',
                    loading: saving,
                    onPressed: when(null, onSave),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
