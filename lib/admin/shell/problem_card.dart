import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// One problem of a form: the [label] of the field it is about, its
/// [message], and [onOpen] to bring that field into view (null when the
/// form has no input for it).
typedef ProblemLine = ({String label, String message, VoidCallback? onOpen});

/// The problems that block saving, summed up in a card at the top of an
/// editor; a line with [ProblemLine.onOpen] leads to its field.
class ProblemCard extends StatelessWidget {
  const ProblemCard({super.key, required this.lines});

  final List<ProblemLine> lines;

  /// The width of the field label column.
  static const _labelWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final danger = text.bodyMedium?.copyWith(color: colors.danger);
    final count = lines.length;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.radii.lg),
        side: BorderSide(color: colors.danger),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.xs,
          children: [
            Text(
              '$count ${count == 1 ? 'problem blocks' : 'problems block'} '
              'saving',
              style: text.titleMedium,
            ),
            Text(
              'Select one to jump to its field.',
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            for (final line in lines)
              InkWell(
                onTap: line.onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _labelWidth,
                        child: Text(line.label, style: text.labelLarge),
                      ),
                      Expanded(child: Text(line.message, style: danger)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets a form bring a field into view and focus it by its name: each
/// input is wrapped in [anchor], and [open] scrolls to it and focuses its
/// first focusable part. The owner disposes it.
class FieldAnchors {
  final _nodes = <String, FocusNode>{};

  FocusNode _node(String field) => _nodes.putIfAbsent(
    field,
    () => FocusNode(
      debugLabel: field,
      canRequestFocus: false,
      skipTraversal: true,
    ),
  );

  /// [child] as the input of [field].
  Widget anchor(String field, Widget child) =>
      Focus(focusNode: _node(field), child: child);

  /// Scrolls to [field] and focuses it; does nothing when it is not shown.
  void open(String field) {
    final node = _nodes[field];
    final context = node?.context;
    if (node == null || context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.2,
      duration: const Duration(milliseconds: 200),
    );
    node.traversalDescendants.firstOrNull?.requestFocus();
  }

  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
  }
}
