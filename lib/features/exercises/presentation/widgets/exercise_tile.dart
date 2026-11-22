import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/widgets/exercise_row.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../favorites_cubit.dart';
import '../vocabulary_labels.dart';

/// An exercise as an [ExerciseRow] opening its detail page at [route]:
/// name, main muscles and equipment, a Custom tag when custom, a star
/// toggling the favourite when [showFavorite], else [tag] at its end;
/// [onOpen] in place of opening the page (the picker's Swap form). With
/// [onSelect] it is the picker's row for [selected] and selects instead,
/// unless not [enabled].
class ExerciseTile extends StatelessWidget {
  const ExerciseTile(
    this.exercise, {
    super.key,
    this.showFavorite = false,
    this.selected = false,
    this.enabled = true,
    this.onSelect,
    this.onOpen,
    this.route = Routes.exercise,
    this.tag,
  });

  final Exercise exercise;
  final bool showFavorite;
  final bool selected;
  final bool enabled;
  final VoidCallback? onSelect;
  final VoidCallback? onOpen;

  /// The detail page's location for an exercise id.
  final String Function(String id) route;

  /// How it relates to the page listing it, e.g. "Variation".
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muscles = l10n.muscleNames(exercise.mainMuscles);
    final detail = exercise.equipment.isEmpty
        ? muscles
        : l10n.exerciseSummary(
            muscles,
            l10n.equipmentNames(exercise.equipment),
          );
    final name = exercise.localized(context).name;
    final favorite =
        showFavorite &&
        context.select(
          (FavoritesCubit cubit) => cubit.state.contains(exercise.id),
        );
    final onSelect = this.onSelect;
    return onSelect == null
        ? ExerciseRow(
            name: name,
            detail: detail,
            favorite: favorite,
            onFavorite: showFavorite
                ? () => context.read<FavoritesCubit>().toggle(exercise.id)
                : null,
            custom: exercise.isCustom,
            relation: tag,
            onTap: onOpen ?? () => context.push(route(exercise.id)),
          )
        : ExerciseRow.pick(
            name: name,
            detail: detail,
            custom: exercise.isCustom,
            selected: selected,
            enabled: enabled,
            onTap: onSelect,
          );
  }
}
