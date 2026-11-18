import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';

/// Today on a day the program has no workout, in the featured block's
/// place: the [next] day ("Pull, Mon, Nov 16"), a walk toward the step
/// goal opening the Steps page ([onSteps]), Log cardio ([onLogCardio]),
/// Start [nextDay] early ([onStartEarly]; with a lock when [locked], as it
/// opens the paywall) and Start empty workout ([onStartEmpty]). Today's
/// [steps] against the [goal]; null [steps] when the app cannot read them.
class RestDayCard extends StatelessWidget {
  const RestDayCard({
    super.key,
    required this.next,
    required this.nextDay,
    required this.steps,
    required this.goal,
    required this.onSteps,
    required this.onLogCardio,
    required this.onStartEarly,
    required this.onStartEmpty,
    this.locked = false,
  });

  final String next;
  final String nextDay;
  final int? steps;
  final int goal;
  final VoidCallback onSteps;
  final VoidCallback onLogCardio;
  final VoidCallback onStartEarly;
  final VoidCallback onStartEmpty;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final steps = this.steps;
    final reached = steps != null && steps >= goal;
    final (walkTitle, walkDetail) = switch (steps) {
      null => (l10n.restDayCardSeeSteps, null),
      _ when reached => (
        l10n.restDayCardGoalReached,
        l10n.restDayCardGoalSteps(steps, goal),
      ),
      _ => (l10n.restDayCardWalk, l10n.restDayCardStepsToGo(goal - steps)),
    };
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                l10n.restDayCardEyebrow,
                style: text.labelMedium!.copyWith(
                  fontWeight: FontWeight.w400,
                  color: p.inkMuted,
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  l10n.restDayCardTitle,
                  style: ForgeStyle.of(context).heading,
                ),
              ),
              Text(l10n.restDayCardNext(next), style: text.bodySmall),
            ],
          ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Suggestion(
                  icon: ForgeIcons.directionsWalk,
                  title: walkTitle,
                  detail: walkDetail,
                  done: reached,
                  onTap: onSteps,
                ),
                Divider(height: 1, thickness: 1, color: p.line),
                _Suggestion(
                  icon: ForgeIcons.directionsRun,
                  title: l10n.cardioLog,
                  detail: l10n.restDayCardCardioDetail,
                  onTap: onLogCardio,
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ForgeButton(
              label: l10n.restDayCardStartEarly(nextDay),
              variant: ForgeButtonVariant.secondary,
              locked: locked,
              onPressed: onStartEarly,
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ForgeButton(
              label: l10n.workoutStartEmpty,
              variant: ForgeButtonVariant.secondary,
              onPressed: onStartEmpty,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return Material(
      color: style.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.radii.lg),
        side: style.cardBorder == 0
            ? BorderSide.none
            : BorderSide(color: style.colors.line, width: style.cardBorder),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A suggestion row: its [icon] in a soft square, [title] over [detail],
/// a chevron; a [done] one tints the square success.
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.done = false,
  });

  final ForgeIconData icon;
  final String title;
  final String? detail;
  final VoidCallback onTap;
  final bool done;

  /// Share of success in the done square's fill.
  static const double _doneTint = 0.15;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final detail = this.detail;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done
                    ? Color.lerp(p.surface, p.success, _doneTint)
                    : p.accentSoft,
                borderRadius: BorderRadius.circular(style.radii.sm),
              ),
              child: ForgeIcon(
                icon,
                size: 18,
                color: done ? p.success : p.onAccentSoft,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Text(title, style: text.titleMedium),
                  if (detail != null)
                    Text(
                      detail,
                      style: text.labelMedium!.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
            ForgeIcon(ForgeIcons.chevronRight, size: 18, color: p.inkMuted),
          ],
        ),
      ),
    );
  }
}
