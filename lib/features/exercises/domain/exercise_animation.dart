import 'package:forge_core/forge_core.dart';

/// An exercise's animation as imported from its approved recipe: the recipe
/// (poses, keys, gear, mistakes) and every approved gear kit, in the format
/// of `tool/animation/recipe.py`. The phone's solver reads them.
class ExerciseAnimation extends Equatable {
  const ExerciseAnimation({required this.recipe, required this.kits});

  final Map<String, Object?> recipe;

  /// Kit name to kit.
  final Map<String, Object?> kits;

  @override
  List<Object?> get props => [recipe, kits];
}
