import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../favorites_cubit.dart';
import '../vocabulary_labels.dart';

/// A row opening the exercise's detail page: name, main muscles and
/// equipment, with a favourite star when [showFavorite].
class ExerciseTile extends StatelessWidget {
  const ExerciseTile(this.exercise, {super.key, this.showFavorite = false});

  final Exercise exercise;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(exercise.localized(context).name),
      subtitle: Text(
        l10n.exerciseSummary(
          l10n.muscleNames(exercise.mainMuscles),
          l10n.equipmentNames(exercise.equipment),
        ),
      ),
      trailing: showFavorite ? FavoriteButton(exercise.id) : null,
      onTap: () => context.push(Routes.exercise(exercise.id)),
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
