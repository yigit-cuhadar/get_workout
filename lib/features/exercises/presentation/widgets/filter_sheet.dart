import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/vocabulary.dart';
import '../equipment_cubit.dart';
import '../library_cubit.dart';
import '../vocabulary_labels.dart';
import 'equipment_picker.dart';

/// The list's filters. Every change applies at once; the bottom button
/// shows how many exercises match and closes the sheet.
Future<void> showFilterSheet(BuildContext context) {
  final library = context.read<LibraryCubit>();
  return showForgeBottomSheet<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: library, child: const FilterSheet()),
  );
}

/// Up to two [names] as they are, the rest counted ("Chest, Lats +2");
/// [any] when there are none.
String _summary(
  List<String> names, {
  required String any,
  required String Function(String shown, int count) more,
}) => switch (names.length) {
  0 => any,
  <= 2 => names.join(', '),
  _ => more(names.take(2).join(', '), names.length - 2),
};

/// The sheet [showFilterSheet] opens; it needs the [LibraryCubit] and the
/// [EquipmentCubit] above it.
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key});

  /// Asks for the equipment first when it is unknown.
  Future<void> _setOnlyDoable(BuildContext context, bool value) async {
    final library = context.read<LibraryCubit>();
    if (value &&
        !library.state.equipmentChosen &&
        !await showEquipmentPicker(context)) {
      return;
    }
    library.setOnlyDoable(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = context.watch<LibraryCubit>();
    final state = library.state;
    final filter = state.filter;
    final owned = context.select((EquipmentCubit cubit) => cubit.state.owned);
    final count = state.results.length;

    /// A row naming the values chosen for one criterion ("Any" when none);
    /// a tap offers all of them in a check sheet over this one.
    ListRow choice<T>({
      required String title,
      required List<T> values,
      required Set<T> selected,
      required String Function(T value) labelOf,
      required ValueChanged<Set<T>> onSaved,
    }) => ListRow(
      title: title,
      value: _summary(
        [
          for (final value in values)
            if (selected.contains(value)) labelOf(value),
        ],
        any: l10n.libraryFilterAny,
        more: l10n.libraryFilterMore,
      ),
      end: ListRowEnd.chevron,
      onTap: () async {
        final picked = await showForgeCheckSheet(
          context: context,
          title: title,
          values: values,
          selected: selected,
          labelOf: labelOf,
          saveLabel: l10n.save,
        );
        if (picked != null) onSaved(picked);
      },
    );

    // Over the sheet: a page's snackbar would draw under it.
    return BlocListener<EquipmentCubit, EquipmentState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (context, _) => showForgeSnackbar(
        context,
        message: l10n.equipmentSaveFailed,
        error: true,
      ),
      child: ForgeBottomSheet(
        title: l10n.libraryFilters,
        headerAction: ForgeButton(
          label: l10n.libraryClearFilters,
          variant: ForgeButtonVariant.text,
          size: ForgeButtonSize.small,
          onPressed: filter.isEmpty ? null : library.clearFilters,
        ),
        action: ForgeButton(
          label: count == 0
              ? l10n.libraryNoResultsTitle
              : l10n.libraryShowResults(count),
          size: ForgeButtonSize.large,
          onPressed: count == 0 ? null : () => Navigator.pop(context),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.md,
            children: [
              ListRowCard(
                children: [
                  ListRow(
                    title: l10n.libraryOnlyFavorites,
                    trailing: ForgeSwitch(
                      value: filter.onlyFavorites,
                      onChanged: library.setOnlyFavorites,
                    ),
                  ),
                  ListRow(
                    title: l10n.libraryOnlyDoable,
                    detail: state.equipmentChosen
                        ? null
                        : l10n.libraryPickEquipmentFirst,
                    trailing: ForgeSwitch(
                      value: filter.onlyDoable,
                      onChanged: (value) => _setOnlyDoable(context, value),
                    ),
                  ),
                  ListRow(
                    title: l10n.equipmentTitle,
                    value: owned == null ? null : '${owned.length}',
                    end: ListRowEnd.chevron,
                    onTap: () => showEquipmentPicker(context),
                  ),
                ],
              ),
              ListRowCard(
                children: [
                  choice(
                    title: l10n.libraryFilterMuscle,
                    values: Muscle.values,
                    selected: filter.muscles,
                    labelOf: l10n.muscleName,
                    onSaved: library.setMuscles,
                  ),
                  choice(
                    title: l10n.libraryFilterEquipment,
                    values: Equipment.values,
                    selected: filter.equipment,
                    labelOf: l10n.equipmentName,
                    onSaved: library.setEquipment,
                  ),
                  choice(
                    title: l10n.libraryFilterMovementPattern,
                    values: MovementPattern.values,
                    selected: filter.movementPatterns,
                    labelOf: l10n.movementPatternName,
                    onSaved: library.setMovementPatterns,
                  ),
                  choice(
                    title: l10n.libraryFilterLevel,
                    values: Level.values,
                    selected: filter.levels,
                    labelOf: l10n.levelName,
                    onSaved: library.setLevels,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
