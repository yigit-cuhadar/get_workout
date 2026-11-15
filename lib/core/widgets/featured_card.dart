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

  /// The outline with a smaller title, a note and its buttons stacked full
  /// width: a prompt to pick a way on (no program yet, or it finished).
  prompt,
}

/// The colour of a prompt's title: a state that is not known yet is muted,
/// one that needs the user's attention is danger.
enum FeaturedTitleTone { ink, muted, danger }

/// A button of a [FeaturedCard]. A [locked] one shows a lock and opens the
/// paywall from [onPressed]; a [danger] one is destructive (a danger
/// outline); a [loading] one shows the ring while its work runs.
class FeaturedAction {
  const FeaturedAction(
    this.label,
    this.onPressed, {
    this.locked = false,
    this.danger = false,
    this.loading = false,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool locked;
  final bool danger;
  final bool loading;
}

/// The line under a [FeaturedCard]'s name: its [icon] (a dumbbell unless
/// given), the [text] and a mono [data] value at its end.
class FeaturedLine {
  const FeaturedLine(this.text, {this.data, this.icon}) : status = null;

  /// A missed day: a calendar, the [text] and the [status] in danger.
  const FeaturedLine.missed(this.text, {required String this.status})
    : data = null,
      icon = null;

  final String text;
  final String? data;
  final String? status;
  final ForgeIconData? icon;
}

/// What a [FeaturedCard.bandError] failed at: the [message] and a retry.
class FeaturedError {
  const FeaturedError(
    this.message, {
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
}

/// One of the summary block's four figures.
class FeaturedStat {
  const FeaturedStat(this.label, this.value);

  final String label;
  final String value;
}

/// The one featured card of a screen in its [form]: an [eyebrow] (with a
/// lock when [locked]) over the [title], then a band's [progress], the
/// [line], a [note], the summary's four [stats] and its buttons, and a
/// band's [rows]; a band may hold a [chart] over its buttons. The first button is the main one; one of [moreActions]
/// sits beside [action], two sit side by side under it; a prompt stacks
/// them all. With [onTap] the whole card opens something and shows a
/// chevron; a band may show its [menu] there instead.
class FeaturedCard extends StatelessWidget {
  const FeaturedCard({
    super.key,
    required this.form,
    required String this.eyebrow,
    required String this.title,
    this.when,
    this.locked = false,
    this.line,
    this.note,
    this.stats = const [],
    this.action,
    this.moreActions = const [],
    this.progress,
    this.rows = const [],
    this.chart,
    this.menu,
    this.onTap,
    this.titleTone = FeaturedTitleTone.ink,
    this.alert,
    this.footActions = const [],
  }) : assert(
         form == FeaturedCardForm.band ||
             (progress == null &&
                 menu == null &&
                 chart == null &&
                 alert == null),
         'Only a band has progress, a chart, a menu and an alert.',
       ),
       assert(menu == null || onTap == null, 'A menu or a chevron, not both.'),
       assert(
         form == FeaturedCardForm.prompt || titleTone == FeaturedTitleTone.ink,
         'Only a prompt tones its title.',
       ),
       error = null,
       loading = false;

  /// A band whose content failed to load: the [eyebrow] alone, then the
  /// [error]'s message in danger beside an outline Retry, over the buttons.
  const FeaturedCard.bandError({
    super.key,
    required String this.eyebrow,
    required FeaturedError this.error,
    this.action,
    this.moreActions = const [],
    this.onTap,
  }) : form = FeaturedCardForm.band,
       title = null,
       when = null,
       locked = false,
       line = null,
       note = null,
       stats = const [],
       progress = null,
       rows = const [],
       chart = null,
       menu = null,
       titleTone = FeaturedTitleTone.ink,
       alert = null,
       footActions = const [],
       loading = false;

  /// The card while what it shows loads: the [eyebrow] over shimmering
  /// bars, never a button.
  const FeaturedCard.loading({super.key, required String this.eyebrow})
    : form = FeaturedCardForm.block,
      title = null,
      when = null,
      locked = false,
      line = null,
      note = null,
      stats = const [],
      action = null,
      moreActions = const [],
      progress = null,
      rows = const [],
      chart = null,
      menu = null,
      onTap = null,
      error = null,
      titleTone = FeaturedTitleTone.ink,
      alert = null,
      footActions = const [],
      loading = true;

  final FeaturedCardForm form;
  final String? eyebrow;
  final String? title;

  /// A band's muted line under its [title]: when it happens ("Today",
  /// "Mon, Nov 16").
  final String? when;
  final bool locked;
  final FeaturedLine? line;

  /// A line of explanation: why a copy is locked, what an empty band
  /// fills with.
  final String? note;
  final List<FeaturedStat> stats;
  final FeaturedAction? action;
  final List<FeaturedAction> moreActions;

  /// A band's progress through what it shows, from 0 to 1, as a bar over
  /// its line and buttons.
  final double? progress;

  /// A band's rows under its buttons ([ListRow]s, e.g. a program's days),
  /// a line between each two and above the first.
  final List<Widget> rows;

  /// A band's chart (a sparkline, or the box that stands in for one)
  /// between its line and its buttons.
  final Widget? chart;
  final FeaturedError? error;

  /// A band's options (an icon button opening a menu) in the chevron's
  /// place, when the band itself opens nothing.
  final Widget? menu;
  final VoidCallback? onTap;

  /// A prompt's title colour; a prompt with no [action] stacks only its
  /// [moreActions], in the secondary form.
  final FeaturedTitleTone titleTone;

  /// A band's line in danger over its progress: something the user must
  /// fix (the training days no longer match the program's days).
  final String? alert;

  /// A band's last row of buttons, side by side under the others (Change
  /// days and Stop); one alone takes the full width.
  final List<FeaturedAction> footActions;
  final bool loading;

  /// Share of on-featured that its quieter text keeps.
  static const double _quiet = 0.72;
  static const double _bodyGap = 14;
  static const double _lineGap = 10;
  static const double _chevronSize = 18;
  static const double _promptTitleSize = 20;
  static const double _promptTitleHeight = 26;

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

    if (form == FeaturedCardForm.prompt) return _prompt(context);

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
                if (title case final title?)
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: text.headlineMedium!.copyWith(color: headInk),
                    ),
                  ),
                if (when case final at?)
                  Text(at, style: text.bodyLarge!.copyWith(color: headQuiet)),
              ],
            ),
          ),
          if (onTap != null)
            ForgeIcon(
              ForgeIcons.chevronRight,
              size: _chevronSize,
              color: headInk,
            )
          else
            ?menu,
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
            for (final row in rows) ...[
              Divider(height: 1, thickness: 1, color: p.line),
              row,
            ],
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
    final progress = this.progress;
    final alert = this.alert;
    final children = [
      if (alert != null)
        Text(alert, style: text.bodySmall!.copyWith(color: p.danger)),
      if (progress != null) Progress.track(value: progress),
      if (line != null)
        Row(
          spacing: _lineGap,
          children: [
            ForgeIcon(
              line.icon ??
                  (line.status == null
                      ? ForgeIcons.fitnessCenter
                      : ForgeIcons.event),
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
      if (error case final error?)
        Row(
          spacing: Gap.sm,
          children: [
            Expanded(
              child: Text(
                error.message,
                style: text.bodySmall!.copyWith(color: p.danger),
              ),
            ),
            ForgeButton(
              label: error.retryLabel,
              onPressed: error.onRetry,
              variant: ForgeButtonVariant.outline,
            ),
          ],
        ),
      if (note != null)
        Text(note, style: text.bodySmall!.copyWith(color: quiet)),
      ?chart,
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
                    for (final stat in stats.skip(row).take(2))
                      Expanded(child: _stat(context, stat, ink, quiet)),
                    // An odd last stat keeps its column.
                    if (row + 1 == stats.length) const Spacer(),
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
      if (footActions.isNotEmpty)
        Row(
          spacing: Gap.sm,
          children: [
            for (final foot in footActions)
              Expanded(child: _button(foot, main: false)),
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

  /// The prompt: a surface card in the accent outline, the eyebrow over a
  /// 20px title, the note and every button stacked full width.
  Widget _prompt(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(style.radii.lg);
    final note = this.note;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: radius,
        border: Border.all(color: p.accent, width: ForgeStyle.featuredBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _lineGap,
          children: [
            Text(
              eyebrow!,
              style: text.bodySmall!.copyWith(fontWeight: FontWeight.w500),
            ),
            Semantics(
              header: true,
              child: Text(
                title!,
                style: text.titleLarge!.copyWith(
                  fontSize: _promptTitleSize,
                  height: _promptTitleHeight / _promptTitleSize,
                  letterSpacing: -0.02 * _promptTitleSize,
                  color: switch (titleTone) {
                    FeaturedTitleTone.ink => p.ink,
                    FeaturedTitleTone.muted => p.inkMuted,
                    FeaturedTitleTone.danger => p.danger,
                  },
                ),
              ),
            ),
            if (note != null)
              Text(note, style: text.bodyMedium!.copyWith(color: p.inkMuted)),
            if (action case final action?) _button(action, main: true),
            for (final more in moreActions) _button(more, main: false),
          ],
        ),
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
      loading: action.loading,
      variant: action.danger
          ? ForgeButtonVariant.danger
          : !main
          ? ForgeButtonVariant.secondary
          : form == FeaturedCardForm.block
          ? ForgeButtonVariant.featured
          : ForgeButtonVariant.primary,
    ),
  );
}
