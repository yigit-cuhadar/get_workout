import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The three forms of a [FeaturedCard]; a screen shows at most one card.
enum FeaturedCardForm {
  /// All featured, its button in featured-action: the workout itself
  /// (Today's next or running workout and its summary).
  block,

  /// A featured band with the name over a surface body: a record's or a
  /// progress page's summary.
  band,

  /// A surface card in a 1.5px accent outline: a suggestion.
  outline,
}

/// A button of a [FeaturedCard]. A [locked] one shows a lock and opens the
/// paywall from [onPressed].
class FeaturedAction {
  const FeaturedAction(this.label, this.onPressed, {this.locked = false});

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool locked;
}

/// The line under a [FeaturedCard]'s name: a dumbbell, the [text] and a
/// mono [data] value at its end.
class FeaturedLine {
  const FeaturedLine(this.text, {this.data}) : status = null;

  /// A missed day: a calendar, the [text] and the [status] in danger.
  const FeaturedLine.missed(this.text, {required String this.status})
    : data = null;

  final String text;
  final String? data;
  final String? status;
}

/// One of the summary block's four figures.
class FeaturedStat {
  const FeaturedStat(this.label, this.value);

  final String label;
  final String value;
}

/// The one featured card of a screen in its [form]: an [eyebrow] (with a
/// lock when [locked]) over the [title], then the [line], a [note], the
/// summary's four [stats] and its buttons. The first button is the main
/// one; one of [moreActions] sits beside [action], two sit side by side
/// under it; a block has no more actions. With [onTap] the whole card opens something and shows a chevron.
class FeaturedCard extends StatelessWidget {
  const FeaturedCard({
    super.key,
    required this.form,
    required String this.eyebrow,
    required String this.title,
    this.locked = false,
    this.line,
    this.note,
    this.stats = const [],
    this.action,
    this.moreActions = const [],
    this.onTap,
  }) : loading = false;

  /// The card while what it shows loads: the [eyebrow] over shimmering
  /// bars, never a button.
  const FeaturedCard.loading({super.key, required String this.eyebrow})
    : form = FeaturedCardForm.block,
      title = null,
      locked = false,
      line = null,
      note = null,
      stats = const [],
      action = null,
      moreActions = const [],
      onTap = null,
      loading = true;

  final FeaturedCardForm form;
  final String? eyebrow;
  final String? title;
  final bool locked;
  final FeaturedLine? line;

  /// A line of explanation: why a copy is locked, what an empty band
  /// fills with.
  final String? note;
  final List<FeaturedStat> stats;
  final FeaturedAction? action;
  final List<FeaturedAction> moreActions;
  final VoidCallback? onTap;
  final bool loading;

  /// Share of on-featured that its quieter text keeps.
  static const double _quiet = 0.72;
  static const double _bodyGap = 14;
  static const double _lineGap = 10;
  static const double _chevronSize = 18;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(style.radii.lg);

    if (loading) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: radius,
          border: _cardBorder(style),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                eyebrow!,
                style: text.bodySmall!.copyWith(fontWeight: FontWeight.w500),
              ),
              const SkeletonBar(
                widthFactor: 0.55,
                height: 28,
                radius: ForgeRadii.button,
              ),
              const SkeletonBar(widthFactor: 0.8, height: 12, radius: 6),
            ],
          ),
        ),
      );
    }

    final featuredHead = form != FeaturedCardForm.outline;
    final headInk = featuredHead ? p.onFeatured : p.ink;
    final headQuiet = featuredHead
        ? p.onFeatured.withValues(alpha: _quiet)
        : p.inkMuted;
    final bodyInk = form == FeaturedCardForm.block ? p.onFeatured : p.ink;
    final bodyQuiet = form == FeaturedCardForm.block
        ? p.onFeatured.withValues(alpha: _quiet)
        : p.inkMuted;
    final band = form == FeaturedCardForm.band;

    final eyebrowStyle = text.bodySmall!.copyWith(
      fontWeight: FontWeight.w500,
      color: headQuiet,
    );
    final head = Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.md,
        Gap.md,
        Gap.md,
        band ? _bodyGap : Gap.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.sm,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: Gap.xs,
                  children: [
                    if (locked)
                      ForgeIcon(ForgeIcons.lock, size: 13, color: headQuiet),
                    Flexible(child: Text(eyebrow!, style: eyebrowStyle)),
                  ],
                ),
                Semantics(
                  header: true,
                  child: Text(
                    title!,
                    style: text.headlineMedium!.copyWith(color: headInk),
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            ForgeIcon(
              ForgeIcons.chevronRight,
              size: _chevronSize,
              color: headInk,
            ),
        ],
      ),
    );

    final body = _body(context, ink: bodyInk, quiet: bodyQuiet);

    final content = switch (form) {
      FeaturedCardForm.band => DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: radius,
          border: _cardBorder(style),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The band covers the card's own line along its edge.
            DecoratedBox(
              decoration: BoxDecoration(
                color: p.featured,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(style.radii.lg),
                ),
                border: Border.all(
                  color: p.featuredBorder,
                  width: ForgeStyle.featuredBorder,
                ),
              ),
              child: head,
            ),
            ?body,
          ],
        ),
      ),
      _ => DecoratedBox(
        decoration: BoxDecoration(
          color: form == FeaturedCardForm.block ? p.featured : p.surface,
          borderRadius: radius,
          border: Border.all(
            color: form == FeaturedCardForm.block ? p.featuredBorder : p.accent,
            width: ForgeStyle.featuredBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [head, ?body],
        ),
      ),
    };

    return Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }

  Border? _cardBorder(ForgeStyle style) => style.cardBorder == 0
      ? null
      : Border.all(color: style.colors.line, width: style.cardBorder);

  Widget? _body(
    BuildContext context, {
    required Color ink,
    required Color quiet,
  }) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final line = this.line;
    final note = this.note;
    final action = this.action;
    final children = [
      if (line != null)
        Row(
          spacing: _lineGap,
          children: [
            ForgeIcon(
              line.status == null ? ForgeIcons.fitnessCenter : ForgeIcons.event,
              size: _chevronSize,
              color: ink,
            ),
            Expanded(
              child: Text(
                line.text,
                style: text.bodyMedium!.copyWith(color: ink),
              ),
            ),
            if (line.data case final data?)
              Text(data, style: style.data.copyWith(color: quiet)),
            if (line.status case final status?)
              Text(
                status,
                style: text.labelMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.danger,
                ),
              ),
          ],
        ),
      if (note != null)
        Text(note, style: text.bodySmall!.copyWith(color: quiet)),
      if (stats.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Gap.xs),
          child: Column(
            spacing: 12,
            children: [
              for (var row = 0; row < stats.length; row += 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.md,
                  children: [
                    for (final stat in stats.sublist(row, row + 2))
                      Expanded(child: _stat(context, stat, ink, quiet)),
                  ],
                ),
            ],
          ),
        ),
      if (action != null)
        if (moreActions.length == 1)
          Row(
            spacing: Gap.sm,
            children: [
              Expanded(child: _button(action, main: true)),
              Expanded(child: _button(moreActions.single, main: false)),
            ],
          )
        else
          _button(action, main: true),
      if (moreActions.length == 2)
        Row(
          spacing: Gap.sm,
          children: [
            for (final more in moreActions)
              Expanded(child: _button(more, main: false)),
          ],
        ),
    ];
    if (children.isEmpty) return null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.md,
        form == FeaturedCardForm.band ? _bodyGap : _lineGap,
        Gap.md,
        Gap.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _bodyGap,
        children: children,
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    FeaturedStat stat,
    Color ink,
    Color quiet,
  ) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          stat.label,
          style: text.labelMedium!.copyWith(
            fontWeight: FontWeight.w400,
            color: quiet,
          ),
        ),
        Text(
          stat.value,
          style: style.dataLg.copyWith(fontWeight: FontWeight.w500, color: ink),
        ),
      ],
    );
  }

  Widget _button(FeaturedAction action, {required bool main}) => SizedBox(
    width: double.infinity,
    child: ForgeButton(
      label: action.label,
      onPressed: action.onPressed,
      locked: action.locked,
      variant: !main
          ? ForgeButtonVariant.secondary
          : form == FeaturedCardForm.block
          ? ForgeButtonVariant.featured
          : ForgeButtonVariant.primary,
    ),
  );
}
