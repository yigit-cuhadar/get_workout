import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/rest.dart';

/// The bottom set panel while a rest runs: "Rest" and the set that comes
/// [next], the [time] left large in mono over a line filled to
/// [progress], then +15 s ([onAddTime]) and Skip rest ([onSkip]).
/// [RestPanel.over] is the moment it ends: "Rest over", 0:00 in accent on
/// a full line, no buttons.
class RestPanel extends StatelessWidget {
  const RestPanel({
    super.key,
    required this.time,
    required this.progress,
    required this.next,
    required VoidCallback this.onAddTime,
    required VoidCallback this.onSkip,
  });

  const RestPanel.over({super.key, required this.time, required this.next})
    : progress = 1,
      onAddTime = null,
      onSkip = null;

  final String time;

  /// How much of the rest has passed, from 0 to 1.
  final double progress;
  final String next;
  final VoidCallback? onAddTime;
  final VoidCallback? onSkip;

  static const padding = EdgeInsets.fromLTRB(14, 12, 14, 18);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final onAddTime = this.onAddTime;
    final onSkip = this.onSkip;
    final over = onAddTime == null || onSkip == null;
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          Row(
            spacing: 10,
            children: [
              Text(
                over ? l10n.restOver : l10n.restPanelTitle,
                style: text.bodySmall!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
              // The line takes all the width the title leaves.
              Expanded(
                child: Text(
                  next,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: style.data.copyWith(
                    fontSize: 11,
                    color: colors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          Text(
            time,
            textAlign: TextAlign.center,
            style: style.dataLg.copyWith(
              fontSize: 46,
              height: 50 / 46,
              fontWeight: FontWeight.w500,
              color: over ? colors.accent : colors.ink,
            ),
          ),
          RestTrack(progress: progress),
          if (!over)
            Row(
              spacing: Gap.sm,
              children: [
                Expanded(
                  child: ForgeButton(
                    label: l10n.restAdd(restExtension.inSeconds),
                    onPressed: onAddTime,
                    variant: ForgeButtonVariant.secondary,
                  ),
                ),
                Expanded(
                  child: ForgeButton(
                    label: l10n.restSkip,
                    onPressed: onSkip,
                    variant: ForgeButtonVariant.secondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The rest's 4px line, filled in accent to [progress] (0 to 1) on
/// surface-sunken.
class RestTrack extends StatelessWidget {
  const RestTrack({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    const radius = BorderRadius.all(Radius.circular(2));
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: radius,
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.accent, borderRadius: radius),
        ),
      ),
    );
  }
}
