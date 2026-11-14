import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// An 8px alignment grid over the use case, off until switched on, for
/// checking spacing against the Gap scale.
class SpacingGridAddon extends WidgetbookAddon<bool> {
  SpacingGridAddon() : super(name: 'Grid');

  @override
  List<Field> get fields => [
    BooleanField(name: 'isEnabled', initialValue: false),
  ];

  @override
  bool valueFromQueryGroup(Map<String, String> group) =>
      valueOf<bool>('isEnabled', group) ?? false;

  @override
  Widget buildUseCase(BuildContext context, Widget child, bool setting) {
    if (!setting) return child;
    return Stack(
      children: [
        child,
        IgnorePointer(
          child: GridPaper(
            color: Colors.red.withAlpha(90),
            interval: 8,
            divisions: 1,
            subdivisions: 1,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
