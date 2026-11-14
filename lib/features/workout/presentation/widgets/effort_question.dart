import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/rest.dart';
import 'rest_panel.dart';

/// One answer of an [EffortQuestion]: its [label] ("Hard", "2", "RPE 8",
/// "Failed") and what it means in one line ([meaning]).
class EffortOption {
  const EffortOption({required this.label, required this.meaning});

  final String label;
  final String meaning;
}

/// The rest running while an [EffortQuestion] is asked: its [time] left,
/// how much of it has passed ([progress], 0 to 1), +15 s ([onAddTime])
/// and Skip ([onSkip]).
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
/// With a [rest], the thin rest line (the time left, +15 s and Skip) sits
/// on top, then the [question] with the set's [values] under it; without
/// one (the rest timer off, mid-superset) the panel opens on [values]
/// ("Set 1 done · 82.5 kg × 8") over the [question]. Both carry Skip
/// ([onSkip]) and the "?" help ([onHelp]), then the scale's [options] as
/// radio rows, [selected] on accent-soft.
class EffortQuestion extends StatelessWidget {
  const EffortQuestion({
    super.key,
    required this.question,
    required this.values,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onSkip,
    required this.onHelp,
    this.rest,
  });

  final String question;
  final String values;
  final List<EffortOption> options;

  /// The chosen option's index, or null.
  final int? selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onSkip;
  final VoidCallback onHelp;
  final EffortRest? rest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final rest = this.rest;
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
          if (rest != null)
            Row(
              spacing: Gap.sm,
              children: [
                Expanded(child: RestTrack(progress: rest.progress)),
                Text(
                  l10n.restRemaining(rest.time),
                  style: style.data.copyWith(color: colors.ink),
                ),
                ForgeButton(
                  label: l10n.restAdd(restExtension.inSeconds),
                  onPressed: rest.onAddTime,
                  variant: ForgeButtonVariant.text,
                ),
                ForgeButton(
                  label: l10n.effortQuestionSkipRest,
                  onPressed: rest.onSkip,
                  variant: ForgeButtonVariant.text,
                ),
              ],
            ),
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
              ForgeButton(
                label: l10n.effortSkip,
                onPressed: onSkip,
                variant: ForgeButtonVariant.text,
              ),
              _HelpButton(onPressed: onHelp),
            ],
          ),
          // What does not fit the panel's share of the page scrolls.
          Flexible(
            child: SingleChildScrollView(
              child: EffortOptions(
                options: options,
                selected: selected,
                onSelected: onSelected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The answers of an effort scale as 44px radio rows, each with its
/// one-line meaning; [selected] on accent-soft.
class EffortOptions extends StatelessWidget {
  const EffortOptions({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<EffortOption> options;
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 2,
    children: [
      for (final (i, option) in options.indexed)
        _OptionRow(
          option: option,
          selected: i == selected,
          onTap: () => onSelected(i),
        ),
    ],
  );
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final EffortOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? colors.accentSoft : null,
            borderRadius: BorderRadius.circular(style.radii.md),
          ),
          child: Row(
            spacing: 12,
            children: [
              _Radio(selected: selected),
              Text(
                option.label,
                style: text.titleMedium!.copyWith(
                  color: selected ? colors.onAccentSoft : colors.ink,
                ),
              ),
              Flexible(
                child: Text(
                  option.meaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall!.copyWith(color: colors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 20px radio of a row: a line-strong ring, accent with an accent dot
/// when [selected].
class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(style.radii.sm),
        border: Border.all(
          color: selected ? colors.accent : colors.lineStrong,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
            )
          : null,
    );
  }
}

/// The "?" opening the effort help: an 18px help icon in ink-muted across
/// a 44px target.
class _HelpButton extends StatelessWidget {
  const _HelpButton({required this.onPressed});

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
