import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_form.dart';
import '../domain/generator_rules.dart';
import 'generator_rules_cubit.dart';

/// The longest split name and info, as the rules allow.
const maxSplitName = 40;
const _maxInfo = 200;

/// Edits split [index] (null: a new one) in a dialog; its id only while it
/// is new.
Future<void> editSplit(BuildContext context, int? index) async {
  final cubit = context.read<GeneratorRulesCubit>();
  final state = cubit.state;
  final draft = state.draft!;
  final split = index == null ? null : draft.splits[index];
  final isNew = split == null || state.rules?.splitIndex(split['id']) == null;
  final edited = await showDialog<JsonMap>(
    context: context,
    builder: (_) => SplitDialog(split: split, idEditable: isNew),
  );
  if (edited == null) return;
  if (index == null) {
    cubit.addItem(['splits'], edited);
  } else {
    cubit.setValue(['splits', index], edited);
  }
}

class SplitDialog extends StatefulWidget {
  const SplitDialog({super.key, required this.split, required this.idEditable});

  final JsonMap? split;
  final bool idEditable;

  @override
  State<SplitDialog> createState() => SplitDialogState();
}

class SplitDialogState extends State<SplitDialog> {
  late final JsonMap _split = widget.split ?? {'id': '', 'l10n': {}};
  late final Map<Object?, Object?> _l10n =
      _split['l10n'] as Map<Object?, Object?>? ?? {};
  late final Map<Object?, Object?> _en =
      _l10n['en'] as Map<Object?, Object?>? ?? {};
  late final _id = TextEditingController(text: '${_split['id'] ?? ''}');
  late final _name = TextEditingController(text: '${_en['name'] ?? ''}');
  late final _info = TextEditingController(text: '${_en['info'] ?? ''}');

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _info.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.split == null ? 'New split' : 'Edit split'),
      content: SizedBox(
        width: maxFormWidth / 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            TextField(
              controller: _id,
              enabled: widget.idEditable,
              decoration: const InputDecoration(
                labelText: 'Id',
                helperText:
                    'Lower case letters, digits and _; fixed once '
                    'published.',
              ),
            ),
            TextField(
              controller: _name,
              maxLength: maxSplitName,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Saved programs are named "<name>, n days".',
              ),
            ),
            TextField(
              controller: _info,
              maxLength: _maxInfo,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Info',
                helperText: 'One line under the split in the app.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, <String, Object?>{
            ..._split,
            'id': _id.text.trim(),
            'l10n': {
              ..._l10n,
              'en': {..._en, 'name': _name.text, 'info': _info.text},
            },
          }),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
