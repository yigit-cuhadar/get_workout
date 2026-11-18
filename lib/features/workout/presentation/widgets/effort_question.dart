import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/rest.dart';
import 'rest_panel.dart';

/// The rest running while an [EffortQuestion] is asked, or above a set
/// picked during it (see [RestLine]): its [time] left,
/// how much of it has passed ([progress], 0 to 1), +15 s ([onAddTime])
/// and Skip rest ([onSkip]).
class EffortRest {
  const EffortRest({
    required this.time,
    required this.progress,
    required this.onAddTime,
    required this.onSkip,
  });

  final String time;
  final double progress;
  final VoidCallback onAddTime;
  final VoidCallback onSkip;
}

/// The bottom panel right after Log set, asking how hard the set was.
///
/// With a [rest], the thin rest line (the time left, +15 s and Skip rest)
/// sits on top, then the [question] with the set's [values] under it;
/// without one (the rest timer off, mid-superset) the panel opens on
/// [values] ("Set 1 done · 82.5 kg × 8") over the [question]. Both carry
/// the "?" help ([onHelp]), then the scale's [options] as radio rows, each
/// label with its one-line meaning as hint, [selected] on accent-soft, and
/// the first-use [tip] under them, scrolling with them so it never hides
/// one.
class EffortQuestion extends StatelessWidget {
  const EffortQuestion({
    super.key,
    required this.question,
    required this.values,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onHelp,
    this.rest,
    this.tip,
  });

  final String question;
  final String values;
  final List<ChoiceOption> options;

  /// The chosen option's index, or null.
  final int? selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onHelp;
  final EffortRest? rest;
  final Widget? tip;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final rest = this.rest;
    final tip = this.tip;
    final questionText = Text(question, style: text.titleMedium);
    final valuesText = Text(
      values,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style.data.copyWith(color: colors.inkMuted),
    );
    return Padding(
      padding: RestPanel.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (rest != null) RestLine(rest),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: rest == null ? 2 : 0,
                  children: rest == null
                      ? [valuesText, questionText]
                      : [questionText, valuesText],
                ),
              ),
              EffortHelpButton(onPressed: onHelp),
            ],
          ),
          // What does not fit the panel's share of the page scrolls.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Gap.md,
                children: [
                  ChoiceGrid.list(
                    options: options,
                    selected: selected,
                    onSelected: onSelected,
                    form: ChoiceListForm.inline,
                  ),
                  ?tip,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The thin line of a running [rest] on top of the bottom panel: its fill,
/// the time left, +15 s and Skip rest. Where the time and buttons do not
/// fit beside [minTrack] of fill (large text), they scale down to fit.
class RestLine extends StatelessWidget {
  const RestLine(this.rest, {super.key});

  final EffortRest rest;

  static const minTrack = 40.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        spacing: Gap.sm,
        children: [
          Expanded(child: RestTrack(progress: rest.progress)),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth - minTrack - Gap.sm,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Gap.sm,
                children: [
                  Text(
                    l10n.restRemaining(rest.time),
                    style: style.data.copyWith(color: style.colors.ink),
                  ),
                  ForgeButton(
                    label: l10n.restAdd(restExtension.inSeconds),
                    onPressed: rest.onAddTime,
                    variant: ForgeButtonVariant.text,
                  ),
                  ForgeButton(
                    label: l10n.restSkip,
                    onPressed: rest.onSkip,
                    variant: ForgeButtonVariant.text,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "?" opening the effort help: an 18px help icon in ink-muted across
/// a 44px target.
class EffortHelpButton extends StatelessWidget {
  const EffortHelpButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: AppLocalizations.of(context).workoutHelp,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: ForgeTheme.tapMin,
        child: Center(
          child: ForgeIcon(
            ForgeIcons.help,
            size: 18,
            color: ForgeStyle.of(context).colors.inkMuted,
          ),
        ),
      ),
    ),
  );
}
