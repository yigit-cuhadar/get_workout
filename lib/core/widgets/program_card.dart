import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';

/// A ready-made program as a card, for a single suggestion: its [name]
/// with the Premium tag when [locked], its [facts] ("days · level ·
/// length") and [tags] (the goal), and a chevron. A [recommended] one
/// carries the eyebrow and, where it applies, the [match] in success.
class ProgramCard extends StatelessWidget {
  const ProgramCard({
    super.key,
    required this.name,
    required this.facts,
    this.tags = const [],
    this.locked = false,
    this.recommended = false,
    this.match,
    required this.onTap,
  }) : assert(match == null || recommended),
       fits = false,
       active = false,
       _row = false;

  /// The catalogue's list row: the [name] with an Active tag when it is
  /// [active] and a Fits you or Premium tag, the [facts] under it; a
  /// chevron unless [locked]. Put rows in a ListRowCard.
  const ProgramCard.row({
    super.key,
    required this.name,
    required this.facts,
    this.fits = false,
    this.active = false,
    this.locked = false,
    required this.onTap,
  }) : tags = const [],
       match = null,
       recommended = false,
       _row = true;

  final String name;
  final String facts;
  final List<String> tags;
  final bool locked;
  final bool recommended;

  /// Why it suits the user ("Matches your goal and days").
  final String? match;

  /// It suits the user's answers: the Fits you tag.
  final bool fits;

  /// It is the user's active program.
  final bool active;
  final VoidCallback onTap;
  final bool _row;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final eyebrow = recommended ? l10n.programCardRecommended : null;
    final chevron = ForgeIcon(
      ForgeIcons.chevronRight,
      size: 18,
      color: p.inkMuted,
    );
    final premium = locked
        ? ForgeTag(l10n.cataloguePremium, kind: ForgeTagKind.premium)
        : null;
    final match = this.match;
    final matchRow = match == null
        ? null
        : Row(
            spacing: 5,
            children: [
              ForgeIcon(ForgeIcons.check, size: 14, color: p.success),
              Flexible(
                child: Text(
                  match,
                  style: text.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.success,
                  ),
                ),
              ),
            ],
          );

    if (_row) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    // A long name wraps beside its tags, which stay on its
                    // first line.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Gap.xs,
                      children: [
                        Flexible(child: Text(name, style: text.titleMedium)),
                        if (active)
                          ForgeTag(
                            l10n.programStateActive,
                            kind: ForgeTagKind.strong,
                          ),
                        if (fits)
                          ForgeTag(
                            l10n.programCardFits,
                            kind: ForgeTagKind.record,
                          ),
                        ?premium,
                      ],
                    ),
                    Text(
                      facts,
                      style: text.labelMedium!.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // A locked row keeps an ink title and loses the chevron.
              if (!locked) chevron,
            ],
          ),
        ),
      );
    }

    return Material(
      color: p.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.radii.lg),
        side: style.cardBorder == 0
            ? BorderSide.none
            : BorderSide(color: p.line, width: style.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 14, 12, 14),
          child: Row(
            spacing: 14,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    if (eyebrow != null)
                      Text(
                        eyebrow,
                        style: text.labelMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: p.inkMuted,
                        ),
                      ),
                    Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium!.copyWith(fontSize: 16),
                          ),
                        ),
                        ?premium,
                      ],
                    ),
                    Text(facts, style: text.bodySmall),
                    if (tags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final tag in tags) ForgeTag(tag)],
                      ),
                    ?matchRow,
                  ],
                ),
              ),
              chevron,
            ],
          ),
        ),
      ),
    );
  }
}
