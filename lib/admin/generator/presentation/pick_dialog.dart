import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import 'rule_fields.dart';

/// Edits a slot's pick: patterns, muscles and mechanic, and pops it.
class PickDialog extends StatefulWidget {
  const PickDialog({super.key, required this.pick});

  final JsonMap pick;

  @override
  State<PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<PickDialog> {
  late final _patterns = {
    ...?(widget.pick['patterns'] as List?)?.map((code) => '$code'),
  };
  late final _muscles = {
    ...?(widget.pick['muscles'] as List?)?.map((code) => '$code'),
  };
  late String? _mechanic = widget.pick['mechanic'] as String?;

  Widget _chips<T extends Coded>(List<T> values, Set<String> selected) => Wrap(
    spacing: Gap.xs,
    runSpacing: Gap.xs,
    children: [
      for (final value in values)
        FilterChip(
          label: Text(codeLabel(value)),
          selected: selected.contains(value.code),
          onSelected: (on) => setState(
            () => on ? selected.add(value.code) : selected.remove(value.code),
          ),
        ),
    ],
  );

  /// [codes] in the order [key] had them, the new ones after in
  /// vocabulary order, so an unchanged pick stays unchanged.
  List<String> _ordered<T extends Coded>(
    String key,
    List<T> values,
    Set<String> codes,
  ) {
    final before = [
      for (final code in widget.pick[key] as List? ?? const []) '$code',
    ];
    return [
      for (final code in before)
        if (codes.contains(code)) code,
      for (final value in values)
        if (codes.contains(value.code) && !before.contains(value.code))
          value.code,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge;
    return AlertDialog(
      title: const Text('Picks an exercise with'),
      content: SizedBox(
        width: maxFormWidth * 0.66,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.sm,
            children: [
              const Hint(
                'An exercise fits when its pattern is one of the patterns, '
                'one of its main muscles is one of the muscles and its '
                'mechanic is the mechanic, each only when given. Patterns or '
                'muscles are needed.',
              ),
              Text('Movement patterns', style: label),
              _chips(MovementPattern.values, _patterns),
              Text('Main muscles', style: label),
              _chips(Muscle.values, _muscles),
              Text('Mechanic', style: label),
              Wrap(
                spacing: Gap.xs,
                children: [
                  for (final mechanic in [null, ...Mechanic.values])
                    ChoiceChip(
                      label: Text(
                        mechanic == null ? 'Any' : codeLabel(mechanic),
                      ),
                      selected: _mechanic == mechanic?.code,
                      onSelected: (_) =>
                          setState(() => _mechanic = mechanic?.code),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final pick = {...widget.pick}
              ..remove('patterns')
              ..remove('muscles')
              ..remove('mechanic');
            Navigator.pop(context, <String, Object?>{
              ...pick,
              if (_patterns.isNotEmpty)
                'patterns': _ordered(
                  'patterns',
                  MovementPattern.values,
                  _patterns,
                ),
              if (_muscles.isNotEmpty)
                'muscles': _ordered('muscles', Muscle.values, _muscles),
              'mechanic': ?_mechanic,
            });
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
