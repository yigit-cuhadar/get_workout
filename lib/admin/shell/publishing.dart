import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

/// The width of a page's history pane.
const historyWidth = 400.0;

/// A publishing page with its [history] pane, when open: beside the page
/// while the page keeps [_minPageWidth], else over the page's right side.
/// The page keeps its place in the tree either way, so it keeps its state.
class PageWithHistory extends StatelessWidget {
  const PageWithHistory({super.key, required this.page, this.history});

  final Widget page;
  final Widget? history;

  /// The least the page is given beside the history pane.
  static const _minPageWidth = 600.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final history = this.history;
      final beside =
          history != null &&
          constraints.maxWidth - historyWidth - 1 >= _minPageWidth;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: page),
                if (history != null && !beside)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: historyWidth.clamp(0, constraints.maxWidth),
                    child: Material(elevation: 8, child: history),
                  ),
              ],
            ),
          ),
          if (beside) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: historyWidth, child: history),
          ],
        ],
      );
    },
  );
}

/// The bar of a page that publishes versions: its count of unpublished
/// changes (and where they are), Discard, the page's [actions] and Review
/// and publish.
class PublishBar extends StatelessWidget {
  const PublishBar({
    super.key,
    required this.count,
    required this.publishing,
    required this.onDiscard,
    required this.onReview,
    this.where,
    this.actions = const [],
  });

  final int count;
  final bool publishing;

  /// Where the changes are, after the count.
  final String? where;
  final VoidCallback? onDiscard;

  /// Null while the changes cannot be published.
  final VoidCallback? onReview;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final where = this.where;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        // The buttons move under the count when both do not fit a line.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            Text(
              publishing
                  ? 'Publishing…'
                  : [
                      '$count unpublished ${count == 1 ? 'change' : 'changes'}',
                      ?where,
                    ].join(' · '),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                OutlinedButton(
                  onPressed: publishing ? null : onDiscard,
                  child: const Text('Discard'),
                ),
                ...actions,
                FilledButton(
                  onPressed: publishing ? null : onReview,
                  child: const Text('Review and publish'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of a [ChangeTable]: where, the value now, the value after
/// publishing.
typedef ChangeRow = (String where, String now, String after);

/// Where / Now / After publishing, the first column named [whereLabel].
class ChangeTable extends StatelessWidget {
  const ChangeTable(this.rows, {super.key, this.whereLabel = 'Where'});

  final List<ChangeRow> rows;
  final String whereLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget cell(String text, [TextStyle? style]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs, horizontal: 2),
      child: Text(text, style: style),
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            cell(whereLabel, heading),
            cell('Now', heading),
            cell('After publishing', heading),
          ],
        ),
        for (final (where, now, after) in rows)
          TableRow(children: [cell(where), cell(now), cell(after)]),
      ],
    );
  }
}

/// The history pane beside a page: its title and Close, an [intro] line,
/// then [failure] with Retry, a loading ring until [loaded], and the
/// versions.
class HistoryPane extends StatelessWidget {
  const HistoryPane({
    super.key,
    required this.onClose,
    required this.onRetry,
    required this.loaded,
    required this.children,
    this.failure,
    this.intro,
  });

  final VoidCallback onClose;
  final VoidCallback onRetry;
  final bool loaded;
  final List<Widget> children;

  /// Why the versions did not load.
  final String? failure;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = this.failure;
    final intro = this.intro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('History', style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (intro != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(
              intro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              if (failure != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.error_outline),
                  title: Text(failure),
                  trailing: TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ),
              if (!loaded && failure == null) const LoadingView(),
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}
