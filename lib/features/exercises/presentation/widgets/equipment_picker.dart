import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/vocabulary.dart';
import '../equipment_cubit.dart';
import '../vocabulary_labels.dart';

/// Lets the user tick the equipment they own. Completes with true once they
/// saved. Bodyweight is always owned, so it is not offered.
Future<bool> showEquipmentPicker(BuildContext context) async {
  final cubit = context.read<EquipmentCubit>();
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, scrollController) => _EquipmentPicker(
        initial: cubit.state.owned ?? const {},
        scrollController: scrollController,
        // Not awaited: offline, a write completes only once it reaches the
        // server, but the cubit sees it from the local cache at once.
        onSave: (owned) => unawaited(cubit.save(owned)),
      ),
    ),
  );
  return saved ?? false;
}

class _EquipmentPicker extends StatefulWidget {
  const _EquipmentPicker({
    required this.initial,
    required this.scrollController,
    required this.onSave,
  });

  final Set<Equipment> initial;
  final ScrollController scrollController;
  final ValueChanged<Set<Equipment>> onSave;

  @override
  State<_EquipmentPicker> createState() => _EquipmentPickerState();
}

class _EquipmentPickerState extends State<_EquipmentPicker> {
  late final Set<Equipment> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        ListTile(
          title: Text(
            l10n.equipmentTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: Text(l10n.equipmentInfo),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            children: [
              for (final item in Equipment.values)
                if (item != Equipment.bodyweight)
                  CheckboxListTile(
                    value: _selected.contains(item),
                    title: Text(l10n.equipmentName(item)),
                    onChanged: (checked) => setState(
                      () => checked == true
                          ? _selected.add(item)
                          : _selected.remove(item),
                    ),
                  ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: SizedBox(
              width: double.infinity,
              child: ForgeButton(
                label: l10n.equipmentSave,
                onPressed: () {
                  widget.onSave(_selected);
                  Navigator.pop(context, true);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
