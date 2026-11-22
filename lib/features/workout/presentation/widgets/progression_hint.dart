import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

/// A thin success-tinted band under the open exercise card when the last
/// session reached the top of the rep range: a trending-up icon and one
/// sentence, [text], with the suggested load. Tapping it puts the load into
/// the set panel through [onTap].
class ProgressionHint extends StatelessWidget {
  const ProgressionHint({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: ForgeTheme.tapMin),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colors.success.withValues(alpha: 0.14),
              colors.surface,
            ),
            borderRadius: BorderRadius.circular(style.radii.md),
          ),
          child: Row(
            spacing: Gap.sm,
            children: [
              ForgeIcon(ForgeIcons.trendingUp, size: 16, color: colors.success),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
