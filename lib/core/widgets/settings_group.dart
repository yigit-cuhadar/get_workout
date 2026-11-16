import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// Space between the parts of a settings page.
const double settingsGap = 10;

/// A group of a settings page: its [title] over a [ListRowCard] of [rows],
/// with an optional [notice] between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    this.notice,
    required this.rows,
  });

  final String title;
  final Widget? notice;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsHeader(title),
      if (notice case final notice?) ...[
        notice,
        const SizedBox(height: settingsGap),
      ],
      ListRowCard(children: rows),
    ],
  );
}

/// The title of a settings group over the part it names, which follows it
/// directly.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    // The title sits closer to its part than the parts to each other.
    padding: const EdgeInsets.fromLTRB(
      Gap.xs,
      Gap.sm,
      Gap.xs,
      settingsGap - Gap.xs,
    ),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

/// [children] one under another, [settingsGap] apart.
class SettingsColumn extends StatelessWidget {
  const SettingsColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: settingsGap,
    children: children,
  );
}
