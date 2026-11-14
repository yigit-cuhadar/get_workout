import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

/// The active preset's colour roles and type scale, as the studio's
/// Temeller section shows them.
class Foundations extends StatelessWidget {
  const Foundations({super.key});

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final c = style.colors;
    final band = GwColors.of(context);
    final text = Theme.of(context).textTheme;
    final roles = {
      'ground': c.ground,
      'surface': c.surface,
      'surface-bar': c.surfaceBar,
      'surface-sunken': c.surfaceSunken,
      'line': c.line,
      'line-strong': c.lineStrong,
      'ink': c.ink,
      'ink-muted': c.inkMuted,
      'ink-subtle': c.inkSubtle,
      'accent': c.accent,
      'on-accent': c.onAccent,
      'accent-soft': c.accentSoft,
      'on-accent-soft': c.onAccentSoft,
      'featured': c.featured,
      'on-featured': c.onFeatured,
      'featured-border': c.featuredBorder,
      'featured-action': c.featuredAction,
      'on-featured-action': c.onFeaturedAction,
      'success': c.success,
      'info': c.info,
      'danger': c.danger,
      'band-below': band.bandBelow,
      'band-in': band.bandIn,
      'band-over': band.bandOver,
    };
    final type = {
      'hero 30/34': text.headlineMedium,
      'page-title 17/22': text.titleLarge,
      'stat 28/32': text.headlineSmall,
      'title 15/20': text.titleMedium,
      'body 14/20': text.bodyMedium,
      'body-sm 13/18': text.bodySmall,
      'label 12/16': text.labelMedium,
      'data-lg 22/26': style.dataLg,
      'data 12/16': style.data,
    };
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final MapEntry(:key, :value) in roles.entries)
              SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: value,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(style.radii.sm),
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(key, style: text.labelMedium),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        for (final MapEntry(:key, :value) in type.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(width: 120, child: Text(key, style: style.data)),
                Expanded(child: Text('Push · 82.5 kg × 8', style: value)),
              ],
            ),
          ),
      ],
    );
  }
}

@widgetbook.UseCase(name: 'Colours and type', type: Foundations)
Widget foundations(BuildContext context) => const Foundations();
