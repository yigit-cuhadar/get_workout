import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/vocabulary.dart';
import '../library_cubit.dart';
import '../vocabulary_labels.dart';
import 'choice_section.dart';
import 'equipment_picker.dart';

/// The list's filters. Every change applies at once.
Future<void> showFilterSheet(BuildContext context) {
  final library = context.read<LibraryCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: library,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (context, scrollController) =>
            _FilterSheet(scrollController: scrollController),
      ),
    ),
  );
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.scrollController});

  final ScrollController scrollController;

  /// Asks for the equipment first when it is unknown.
  Future<void> _setOnlyDoable(
    BuildContext context,
    bool value,
    bool equipmentChosen,
  ) async {
    final library = context.read<LibraryCubit>();
    if (value && !equipmentChosen && !await showEquipmentPicker(context)) {
      return;
    }
    library.setOnlyDoable(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final library = context.read<LibraryCubit>();
        final filter = state.filter;
        return ListView(
          controller: scrollController,
          children: [
            ListTile(
              title: Text(
                l10n.libraryFilters,
                style: theme.textTheme.titleLarge,
              ),
              trailing: TextButton(
                onPressed: filter.isEmpty ? null : library.clearFilters,
                child: Text(l10n.libraryClearFilters),
              ),
            ),
            SwitchListTile(
              title: Text(l10n.libraryOnlyFavorites),
              value: filter.onlyFavorites,
              onChanged: library.setOnlyFavorites,
            ),
            SwitchListTile(
              title: Text(l10n.libraryOnlyDoable),
              subtitle: state.equipmentChosen
                  ? null
                  : Text(l10n.libraryPickEquipmentFirst),
              value: filter.onlyDoable,
              onChanged: (value) =>
                  _setOnlyDoable(context, value, state.equipmentChosen),
            ),
            ListTile(
              title: Text(l10n.equipmentTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showEquipmentPicker(context),
            ),
            ChoiceSection(
              title: l10n.libraryFilterMuscle,
              values: Muscle.values,
              selected: filter.muscles,
              labelOf: l10n.muscleName,
              onToggle: library.toggleMuscle,
            ),
            ChoiceSection(
              title: l10n.libraryFilterEquipment,
              values: Equipment.values,
              selected: filter.equipment,
              labelOf: l10n.equipmentName,
              onToggle: library.toggleEquipment,
            ),
            ChoiceSection(
              title: l10n.libraryFilterLevel,
              values: Level.values,
              selected: filter.levels,
              labelOf: l10n.levelName,
              onToggle: library.toggleLevel,
            ),
            ChoiceSection(
              title: l10n.libraryFilterMovementPattern,
              values: MovementPattern.values,
              selected: filter.movementPatterns,
              labelOf: l10n.movementPatternName,
              onToggle: library.toggleMovementPattern,
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: ForgeButton(
                  label: l10n.libraryDone,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
