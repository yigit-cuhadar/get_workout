import 'package:material_ui/material_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import 'all_forms.dart';
import 'grid_addon.dart';
import 'main.directories.g.dart';

void main() => runApp(const GetWorkoutWidgetbook());

/// GetWorkout's own components in every form and state of their GetWorkout
/// Studio cards, in each preset and brightness.
@widgetbook.App()
class GetWorkoutWidgetbook extends StatelessWidget {
  const GetWorkoutWidgetbook({super.key});

  @override
  Widget build(BuildContext context) => Widgetbook(
    directories: withAllForms(directories),
    // Widgetbook's material builder and theme addon still use the
    // deprecated package:flutter/material.dart types; these use material_ui.
    appBuilder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(child: child),
    ),
    addons: [
      ThemeAddon<ThemeData>(
        themeBuilder: (context, theme, child) => Theme(
          data: theme,
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: child,
            ),
          ),
        ),
        themes: [
          for (final preset in AppPreset.values) ...[
            WidgetbookTheme(
              name: '${preset.forge.name} · Light',
              data: preset.lightTheme(),
            ),
            WidgetbookTheme(
              name: '${preset.forge.name} · Dark',
              data: preset.darkTheme(),
            ),
          ],
        ],
      ),
      ViewportAddon([
        Viewports.none,
        IosViewports.iPhone13,
        IosViewports.iPhoneSE,
        AndroidViewports.samsungGalaxyS20,
      ]),
      TextScaleAddon(min: 1, max: 2, divisions: 4),
      SpacingGridAddon(),
    ],
  );
}
