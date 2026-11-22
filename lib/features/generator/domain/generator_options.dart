import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';

/// A split's name and the line under it, in one language.
typedef SplitText = ({String name, String info});

/// The days, levels and goals one of a split's templates is for.
class SplitFit extends Equatable {
  const SplitFit({required this.days, required this.levels, this.goals});

  final int days;
  final Set<Level> levels;

  /// Null: every goal.
  final Set<Goal>? goals;

  bool fits(int days, Level level, Goal goal) =>
      days == this.days &&
      levels.contains(level) &&
      (goals?.contains(goal) ?? true);

  @override
  List<Object?> get props => [days, levels, goals];
}

class GeneratorSplit extends Equatable {
  const GeneratorSplit({
    required this.id,
    required this.l10n,
    required this.fits,
  });

  /// The language [text] falls back to; every split has it.
  static const fallbackLanguage = 'en';

  final String id;

  /// By language code.
  final Map<String, SplitText> l10n;
  final List<SplitFit> fits;

  SplitText text(String language) => l10n[language] ?? l10n[fallbackLanguage]!;

  @override
  List<Object?> get props => [id, l10n, fits];
}

/// What the questions offer (`generator/options`).
class GeneratorOptions extends Equatable {
  const GeneratorOptions({
    required this.splits,
    required this.sessionMinutes,
    required this.maxFocusAreas,
    required this.maxSkipAreas,
  });

  /// In the order the split question lists them.
  final List<GeneratorSplit> splits;
  final List<int> sessionMinutes;
  final int maxFocusAreas;
  final int maxSkipAreas;

  /// The splits with a template for [days], [level] and [goal].
  List<GeneratorSplit> splitsFitting(int days, Level level, Goal goal) => [
    for (final split in splits)
      if (split.fits.any((fit) => fit.fits(days, level, goal))) split,
  ];

  /// The session length picked before the user picks one: 60 minutes when
  /// offered, else the middle one.
  int get defaultSessionMinutes => sessionMinutes.contains(60)
      ? 60
      : sessionMinutes[sessionMinutes.length ~/ 2];

  @override
  List<Object?> get props => [
    splits,
    sessionMinutes,
    maxFocusAreas,
    maxSkipAreas,
  ];
}
