import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';

/// The biggest new record as a featured block: "New record", its [value]
/// ("82.5 kg × 8") and a [line] with the exercise, e1RM and gain.
class RecordHighlight extends StatelessWidget {
  const RecordHighlight({super.key, required this.value, required this.line});

  final String value;
  final String line;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final quiet = p.onFeatured.withValues(alpha: 0.72);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: p.featured,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: Border.all(
          color: p.featuredBorder,
          width: ForgeStyle.featuredBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.xs,
        children: [
          Text(
            AppLocalizations.of(context).recordNew,
            style: text.bodySmall!.copyWith(
              fontWeight: FontWeight.w500,
              color: quiet,
            ),
          ),
          Text(
            value,
            style: style.dataLg.copyWith(
              fontSize: 36,
              height: 40 / 36,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.72,
              color: p.onFeatured,
            ),
          ),
          Text(line, style: text.bodySmall!.copyWith(color: quiet)),
        ],
      ),
    );
  }
}

/// One record of a [RecordList].
class RecordItem {
  const RecordItem({
    required this.name,
    required this.detail,
    required this.value,
    required this.gain,
  });

  /// The exercise.
  final String name;

  /// Which records it beat ("Heaviest weight · Best e1RM").
  final String detail;

  /// The set that beat them ("82.5 kg × 6").
  final String value;

  /// The gain with its unit ("+2.5 kg").
  final String gain;
}

/// Records as one card: a trophy in success over "2 new records", then a
/// row per record with its kinds and set ("Heaviest weight · 82.5 kg × 6")
/// and its gain as a record tag.
class RecordList extends StatelessWidget {
  const RecordList({super.key, required List<RecordItem> this.records})
    : closest = null,
      message = null;

  /// No new record, said in one sentence on a plain card (a workout's
  /// summary): how close the best came, or that records start now.
  const RecordList.message({super.key, required String this.message})
    : records = null,
      closest = null;

  /// No new record: a muted trophy row. After the first workout it says
  /// records start now; later [closest] says how close the best came.
  const RecordList.none({super.key, this.closest})
    : records = null,
      message = null;

  final List<RecordItem>? records;
  final String? closest;
  final String? message;

  static const double _trophy = 36;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final records = this.records;
    final closest = this.closest;
    final message = this.message;
    final trophy = Container(
      width: _trophy,
      height: _trophy,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.surfaceSunken),
      child: ForgeIcon(ForgeIcons.emojiEvents, size: 18, color: p.inkMuted),
    );
    final name = text.bodyLarge!.copyWith(fontWeight: FontWeight.w500);
    final small = text.labelMedium!.copyWith(
      fontWeight: FontWeight.w400,
      color: p.inkMuted,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: p.line, width: style.cardBorder),
      ),
      child: message != null
          ? Text(message, style: text.bodyMedium!.copyWith(color: p.inkMuted))
          : records == null
          ? Row(
              spacing: 12,
              children: [
                trophy,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        closest == null
                            ? l10n.recordFirstTitle
                            : l10n.recordNoneTitle,
                        style: name,
                      ),
                      Text(closest ?? l10n.recordFirstDetail, style: small),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(
                    spacing: Gap.sm,
                    children: [
                      ForgeIcon(
                        ForgeIcons.emojiEvents,
                        size: 18,
                        color: p.success,
                      ),
                      Expanded(
                        child: Text(
                          l10n.recordNewCount(records.length),
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final (i, record) in records.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: i == 0
                        ? null
                        : BoxDecoration(
                            border: Border(top: BorderSide(color: p.line)),
                          ),
                    child: Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              Text(
                                record.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: name,
                              ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: '${record.detail} · '),
                                    TextSpan(
                                      text: record.value,
                                      style: style.data.copyWith(
                                        fontSize: small.fontSize,
                                        color: p.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                style: small,
                              ),
                            ],
                          ),
                        ),
                        ForgeTag(record.gain, kind: ForgeTagKind.record),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
