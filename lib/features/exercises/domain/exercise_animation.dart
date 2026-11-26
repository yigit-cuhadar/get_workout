import 'package:forge_core/forge_core.dart';

/// An exercise's animation as imported from its approved recipe: the recipe
/// (poses, keys, gear, mistakes) and every approved gear kit, in the format
/// of `tool/animation/recipe.py`. The phone's solver reads them.
class ExerciseAnimation extends Equatable {
  const ExerciseAnimation({required this.recipe, required this.kits});

  final Map<String, Object?> recipe;

  /// Kit name to kit.
  final Map<String, Object?> kits;

  /// What it plays: the correct form, then each mistake a pose shows, in the
  /// order of the catalogue's `mistakes`. Throws when the recipe's
  /// `mistakes` are malformed.
  List<AnimationClip> get clips {
    final mistakes = recipe['mistakes'] as List<Object?>? ?? const [];
    return [
      const AnimationClip.correct(),
      ...[
        for (final (i, mistake)
            in mistakes.cast<Map<String, Object?>>().indexed)
          if (mistake['shown'] != false)
            AnimationClip.mistake(i, mistake['line']! as int),
      ]..sort((a, b) => a.line!.compareTo(b.line!)),
    ];
  }

  @override
  List<Object?> get props => [recipe, kits];
}

/// One clip of an [ExerciseAnimation]: the correct form, or entry [mistake]
/// of the recipe's `mistakes`, which shows the catalogue `mistakes` text on
/// [line].
class AnimationClip extends Equatable {
  const AnimationClip.correct() : mistake = null, line = null;

  const AnimationClip.mistake(int this.mistake, int this.line);

  final int? mistake;
  final int? line;

  @override
  List<Object?> get props => [mistake, line];
}
