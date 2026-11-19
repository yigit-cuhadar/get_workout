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

  /// The outline with a 15px title and a muted line, no button: the way to
  /// a target (Body Compare, Measurement summary).
  target,
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

/// Which way a [FeaturedStat]'s change went: a gain, a drop, or neither
/// good nor bad (a duration, no change).
enum FeaturedChangeTone { gain, drop, neutral }

/// One of the summary block's four figures, with its [change] since last
/// time under the value.
class FeaturedStat {
  const FeaturedStat(
    this.label,
    this.value, {
    this.change,
    this.tone = FeaturedChangeTone.neutral,
  });

  final String label;
  final String value;
  final String? change;
  final FeaturedChangeTone tone;
}

/// The one featured card of a screen in its [form]: an [eyebrow] (with a
/// lock when [locked]) over the [title] on one line and a band's
/// [titleAside], then a
/// band's [progress] (in [progressSegments] under [progressLabel] and
/// [progressDetail]), the
/// [line], a [note], the summary's four [stats] and its buttons, and a
/// band's or an outline's [rows]; a band may hold a [chart] over its
/// buttons. The first button is the main one; one of [moreActions]
/// sits beside [action], two sit side by side under it; a prompt stacks
/// them all. With [onTap] the whole card opens something and shows a
/// chevron; a band with a [menu] shows the menu there instead, with no
/// other mark.
class FeaturedCard extends StatelessWidget {
  const FeaturedCard({
    super.key,
    required this.form,
    required String this.eyebrow,
    required String this.title,
    this.titleAside,
    this.when,
    this.origin,
    this.onOrigin,
    this.locked = false,
    this.line,
    this.note,
    this.stats = const [],
    this.action,
    this.moreActions = const [],
    this.progress,
    this.progressSegments,
    this.progressLabel,
    this.progressDetail,
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
                 progressLabel == null &&
                 titleAside == null &&
                 menu == null &&
                 chart == null &&
                 alert == null),
         'Only a band has progress, a title aside, a chart, a menu and an '
         'alert.',
       ),
       assert(onOrigin == null || origin != null, 'A link needs its text.'),
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
       origin = null,
       onOrigin = null,
       locked = false,
       line = null,
       note = null,
       stats = const [],
       progress = null,
       progressSegments = null,
       progressLabel = null,
       progressDetail = null,
       titleAside = null,
       rows = const [],
       chart = null,
       menu = null,
       titleTone = FeaturedTitleTone.ink,
       alert = null,
       footActions = const [],
       loading = false;

  /// The way to a target: the [title] ("Target 78 kg") over a muted
  /// [note] ("At this pace, around Dec 28.") in the accent outline.
  const FeaturedCard.target({
    super.key,
    required String this.title,
    required String this.note,
  }) : form = FeaturedCardForm.target,
       eyebrow = null,
       origin = null,
       onOrigin = null,
       when = null,
       locked = false,
       line = null,
       stats = const [],
       action = null,
       moreActions = const [],
       progress = null,
       progressSegments = null,
       progressLabel = null,
       progressDetail = null,
       titleAside = null,
       rows = const [],
       chart = null,
       menu = null,
       onTap = null,
       error = null,
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
      origin = null,
      onOrigin = null,
      locked = false,
      line = null,
      note = null,
      stats = const [],
      action = null,
      moreActions = const [],
      progress = null,
      progressSegments = null,
      progressLabel = null,
      progressDetail = null,
      titleAside = null,
      rows = const [],
      chart = null,
      menu = null,
      onTap = null,
      error = null,
      titleTone = FeaturedTitleTone.ink,
      alert = null,
      footActions = const [],
      loading = true;

  /// A band while what it shows loads: a sunken band over a row of four
  /// shimmering figures (a past workout's page).
  const FeaturedCard.bandLoading({super.key})
    : form = FeaturedCardForm.band,
      eyebrow = null,
      title = null,
      when = null,
      origin = null,
      onOrigin = null,
      locked = false,
      line = null,
      note = null,
      stats = const [],
      action = null,
      moreActions = const [],
      progress = null,
      progressSegments = null,
      progressLabel = null,
      progressDetail = null,
      titleAside = null,
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

  /// A band's mono value beside its [title], quieter: what changed
  /// ("−2.1 kg in 12 weeks").
  final String? titleAside;

  /// A band's muted line under its [title]: when it happens ("Today",
  /// "Mon, Nov 16") or what goes with it ("18 % body fat · Nov 14").
  final String? when;

  /// A band's line under its [title] saying where it came from (a past
  /// workout's program and week); underlined and opening it with
  /// [onOrigin].
  final String? origin;
  final VoidCallback? onOrigin;
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

  /// The parts the [progress] bar is cut into (a program's weeks).
  final int? progressSegments;

  /// A line over the [progress] bar: [progressLabel] at its start
  /// ("Week 1 of 8"), a mono [progressDetail] at its end ("1 of 3 days
  /// this week"). It stands without a bar too.
  final String? progressLabel;
  final String? progressDetail;

  /// A band's or an outline's rows under its buttons ([ListRow]s, e.g. a
  /// program's days), a line between each two and above the first.
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

  /// Share of success or danger in a stat's change on the featured fill.
  static const double _changeTint = 0.45;
  static const double _bodyGap = 14;
  static const double _lineGap = 10;
  static const double _chevronSize = 18;
  static const double _loadingBandHeight = 78;

  /// A band's figures sit side by side, four at most.
  static const int _bandFigures = 4;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(style.radii.lg);

    if (loading && form == FeaturedCardForm.band) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: radius,
          border: _cardBorder(style),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _loadingBandHeight,
              decoration: BoxDecoration(
                color: p.surfaceSunken,
                borderRadius: BorderRadius.vertical(top: radius.topLeft),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 12, Gap.md, 14),
              child: Row(
                spacing: Gap.sm,
                children: [
                  for (var i = 0; i < _bandFigures; i++)
                    const Expanded(
                      child: SkeletonBar(widthFactor: 0.8, height: 22),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
    if (form == FeaturedCardForm.target) {
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
            spacing: 12,
            children: [
              Semantics(
                header: true,
                child: Text(title!, style: text.titleMedium),
              ),
              Text(note!, style: text.bodyMedium!.copyWith(color: p.inkMuted)),
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
                if (title case final title?)
                  Semantics(
                    header: true,
                    child: _OneLineTitle(
                      title,
                      style: text.headlineMedium!.copyWith(color: headInk),
                      aside: titleAside,
                      asideStyle: style.data.copyWith(color: headQuiet),
                    ),
                  ),
                if (when case final at?)
                  Text(at, style: text.bodyLarge!.copyWith(color: headQuiet)),
                if (origin case final origin?) _origin(origin, headQuiet, text),
              ],
            ),
          ),
          if (onTap != null && menu == null)
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
          children: [
            head,
            ?body,
            for (final row in rows) ...[
              Divider(height: 1, thickness: 1, color: p.line),
              row,
            ],
          ],
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
      if (progressLabel case final label?)
        // The detail goes under the label when both do not fit (larger
        // text).
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: Gap.sm,
          runSpacing: 2,
          children: [
            Text(label, style: text.bodySmall!.copyWith(color: ink)),
            if (progressDetail case final detail?)
              Text(detail, style: style.data.copyWith(color: quiet)),
          ],
        ),
      if (progress != null)
        if (progressSegments case final segments?)
          Progress.segmented(value: progress, segments: segments)
        else
          Progress.track(value: progress),
      if (line != null) _line(context, line, ink, quiet),
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
      if (stats.isNotEmpty && form == FeaturedCardForm.band)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.sm,
          children: [
            for (final stat in stats.take(_bandFigures))
              Expanded(child: _figure(context, stat, ink, quiet)),
          ],
        )
      else if (stats.isNotEmpty)
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
          _buttonRow(context, [action, moreActions.single], firstMain: true)
        else
          _button(action, main: true),
      if (moreActions.length == 2) _buttonRow(context, moreActions),
      if (footActions.isNotEmpty) _buttonRow(context, footActions),
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
  /// heading, the note and every button stacked full width.
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
                style: style.heading.copyWith(
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
        if (stat.change case final change?)
          Text(
            change,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.data.copyWith(
              fontSize: 12,
              color: switch (stat.tone) {
                FeaturedChangeTone.gain => Color.lerp(
                  ink,
                  style.colors.success,
                  _changeTint,
                ),
                FeaturedChangeTone.drop => Color.lerp(
                  ink,
                  style.colors.danger,
                  _changeTint,
                ),
                FeaturedChangeTone.neutral => quiet,
              },
            ),
          ),
      ],
    );
  }

  Widget _origin(String origin, Color color, TextTheme text) {
    final onOrigin = this.onOrigin;
    final label = Text(
      origin,
      style: text.bodySmall!.copyWith(
        color: color,
        decoration: onOrigin == null ? null : TextDecoration.underline,
        decorationColor: color,
      ),
    );
    if (onOrigin == null) return label;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOrigin,
        child: label,
      ),
    );
  }

  /// A band's figure: the value in mono over its label.
  Widget _figure(
    BuildContext context,
    FeaturedStat stat,
    Color ink,
    Color quiet,
  ) {
    final style = ForgeStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          stat.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.data.copyWith(fontSize: 15, height: 20 / 15, color: ink),
        ),
        Text(
          stat.label,
          style: Theme.of(context).textTheme.labelSmall!
              .copyWith(fontWeight: FontWeight.w400, color: quiet),
        ),
      ],
    );
  }

  /// The info line: its icon, text, data and status in a row; at larger
  /// text the data and status go under the text, which wraps.
  Widget _line(
    BuildContext context,
    FeaturedLine line,
    Color ink,
    Color quiet,
  ) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final scaled = MediaQuery.textScalerOf(context).scale(1) > 1;
    final label = Text(line.text, style: text.bodyMedium!.copyWith(color: ink));
    final trailing = [
      if (line.data case final data?)
        Text(data, style: style.data.copyWith(color: quiet)),
      if (line.status case final status?)
        Text(
          status,
          style: text.labelMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: style.colors.danger,
          ),
        ),
    ];
    return Row(
      crossAxisAlignment: scaled
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
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
        if (scaled)
          Expanded(
            child: Wrap(
              spacing: _lineGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [label, ...trailing],
            ),
          )
        else ...[
          Expanded(child: label),
          ...trailing,
        ],
      ],
    );
  }

  /// [actions] side by side in equal halves, the first the main one when
  /// [firstMain]; stacked full width when a label would not fit its half
  /// (larger text).
  Widget _buttonRow(
    BuildContext context,
    List<FeaturedAction> actions, {
    bool firstMain = false,
  }) {
    final buttons = [
      for (final (i, action) in actions.indexed)
        _button(action, main: firstMain && i == 0),
    ];
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler.scale(1) <= 1) {
      return Row(
        spacing: Gap.sm,
        children: [for (final button in buttons) Expanded(child: button)],
      );
    }
    final labelStyle = Theme.of(context).textTheme.labelLarge!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - Gap.sm) / 2;
        final fits = actions.every((action) {
          final label = TextPainter(
            text: TextSpan(text: action.label, style: labelStyle),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final width =
              label.width + 2 * Gap.md + (action.locked ? _lockRoom : 0);
          label.dispose();
          return width <= half;
        });
        return fits
            ? Row(
                spacing: Gap.sm,
                children: [
                  for (final button in buttons) Expanded(child: button),
                ],
              )
            : Column(spacing: Gap.sm, children: buttons);
      },
    );
  }

  /// The lock icon and its gap in a locked button.
  static const double _lockRoom = 16 + Gap.xs;

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

/// [title] on one line with an [aside] after it: the title alone shrinks
/// from [style]'s size down to [_minSize] until both fit, then is cut with
/// "…"; the aside keeps its whole width. The line keeps its height as the
/// type shrinks.
class _OneLineTitle extends StatelessWidget {
  const _OneLineTitle(
    this.title, {
    required this.style,
    required this.aside,
    required this.asideStyle,
  });

  final String title;
  final TextStyle style;
  final String? aside;
  final TextStyle asideStyle;

  static const double _minSize = 18;
  static const double _asideGap = 12;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final base = style.fontSize!;
    final lineHeight = base * style.height!;
    TextStyle sized(double size) => style.copyWith(
      fontSize: size,
      height: lineHeight / size,
      letterSpacing: (style.letterSpacing ?? 0) * size / base,
    );
    double width(TextSpan span) {
      final painter = TextPainter(
        text: span,
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final aside = this.aside;
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = aside == null
            ? constraints.maxWidth
            : constraints.maxWidth -
                  _asideGap -
                  width(TextSpan(text: aside, style: asideStyle));
        var size = base;
        while (size > _minSize &&
            width(TextSpan(text: title, style: sized(size))) > room) {
          size = (size - 1).clamp(_minSize, base);
        }
        final name = Text(
          title,
          style: sized(size),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        if (aside == null) return name;
        // At large text sizes the aside alone may leave the title too little
        // room: it then goes under the title instead of beside it.
        if (room < constraints.maxWidth / 2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              Text(aside, style: asideStyle),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: _asideGap,
          children: [
            Flexible(child: name),
            Text(aside, style: asideStyle, maxLines: 1),
          ],
        );
      },
    );
  }
}
