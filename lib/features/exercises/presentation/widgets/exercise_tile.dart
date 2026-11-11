import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../favorites_cubit.dart';
import '../vocabulary_labels.dart';

/// A row opening the exercise's detail page: name, main muscles and
/// equipment, marked when custom, with a favourite star when [showFavorite].
/// With [onSelect] it shows a checkbox for [selected] and selects instead.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile(
    this.exercise, {
    super.key,
    this.showFavorite = false,
    this.selected = false,
    this.onSelect,
  });

  final Exercise exercise;
  final bool showFavorite;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muscles = l10n.muscleNames(exercise.mainMuscles);
    final summary = exercise.equipment.isEmpty
        ? muscles
        : l10n.exerciseSummary(
            muscles,
            l10n.equipmentNames(exercise.equipment),
          );
    final onSelect = this.onSelect;
    return ListTile(
      leading: onSelect == null
          ? null
          : Checkbox(value: selected, onChanged: (_) => onSelect()),
      selected: selected,
      title: Text(exercise.localized(context).name),
      subtitle: Text(exercise.isCustom ? l10n.customSummary(summary) : summary),
      trailing: showFavorite ? FavoriteButton(exercise.id) : null,
      onTap: onSelect ?? () => context.push(Routes.exercise(exercise.id)),
    );
  }
}

/// A star that adds the exercise to, or removes it from, the favourites.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton(this.exerciseId, {super.key});

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final favorite = context.select(
      (FavoritesCubit cubit) => cubit.state.contains(exerciseId),
    );
    return IconButton(
      isSelected: favorite,
      icon: const Icon(Icons.star_border),
      selectedIcon: const Icon(Icons.star),
      tooltip: favorite ? l10n.favoriteRemove : l10n.favoriteAdd,
      onPressed: () => context.read<FavoritesCubit>().toggle(exerciseId),
    );
  }
}
