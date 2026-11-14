import 'package:flutter/material.dart';

import 'theme.dart';

/// Debug builds only: switches the app between the studio's presets so they
/// can be compared on a device before one ships.
class PresetPicker extends StatelessWidget {
  const PresetPicker(this.preset, {super.key});

  final ValueNotifier<AppPreset> preset;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: preset,
    builder: (context, current, _) => ListTile(
      title: const Text('Preset (debug)'),
      trailing: DropdownButton<AppPreset>(
        value: current,
        items: [
          for (final p in AppPreset.values)
            DropdownMenuItem(value: p, child: Text(p.forge.name)),
        ],
        onChanged: (p) => preset.value = p ?? current,
      ),
    ),
  );
}
