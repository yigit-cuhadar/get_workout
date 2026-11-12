import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import '../domain/generator_answers.dart';

/// The questions, in the order they are asked.
enum GeneratorStep {
  goal,
  level,
  days,
  session,
  equipment,
  focus,
  excluded,
  easyArea,
  split,
}

/// What the user already told the app; each prefills its question.
typedef GeneratorPrefill = ({
  Goal? goal,
  Level? level,
  int? daysPerWeek,
  Set<Equipment>? equipment,
});

class GeneratorQuestionsState extends Equatable {
  const GeneratorQuestionsState({
    this.step = GeneratorStep.goal,
    this.goal,
    this.level,
    this.daysPerWeek,
    this.sessionMinutes = defaultSessionMinutes,
    this.equipment,
    this.focus = const {},
    this.excluded = const {},
    this.easyArea,
    this.split,
  });

  static const defaultSessionMinutes = 60;

  final GeneratorStep step;
  final Goal? goal;
  final Level? level;
  final int? daysPerWeek;
  final int sessionMinutes;

  /// Null until chosen; empty is bodyweight only.
  final Set<Equipment>? equipment;
  final Set<Muscle> focus;
  final Set<String> excluded;
  final EasyArea? easyArea;
  final TrainingSplit? split;

  bool get isLast => step == GeneratorStep.values.last;

  /// Whether the question on screen is answered. The later ones have an
  /// answer from the start: none, or the best split.
  bool get answered => switch (step) {
    GeneratorStep.goal => goal != null,
    GeneratorStep.level => level != null,
    GeneratorStep.days => daysPerWeek != null,
    GeneratorStep.equipment => equipment != null,
    GeneratorStep.split => split == null || splitFits(split!),
    _ => true,
  };

  /// Whether [split] can be trained on the days chosen.
  bool splitFits(TrainingSplit split) => (daysPerWeek ?? 0) >= split.minDays;

  /// Null until every question needing an answer has one.
  GeneratorAnswers? get answers {
    final goal = this.goal;
    final level = this.level;
    final days = daysPerWeek;
    final equipment = this.equipment;
    if (goal == null || level == null || days == null || equipment == null) {
      return null;
    }
    return GeneratorAnswers(
      goal: goal,
      level: level,
      daysPerWeek: days,
      sessionMinutes: sessionMinutes,
      equipment: equipment,
      focus: focus,
      excluded: excluded,
      easyArea: easyArea,
      split: split,
    );
  }

  GeneratorQuestionsState copyWith({
    GeneratorStep? step,
    Goal? goal,
    Level? level,
    int? daysPerWeek,
    int? sessionMinutes,
    Set<Equipment>? equipment,
    Set<Muscle>? focus,
    Set<String>? excluded,
    EasyArea? Function()? easyArea,
    TrainingSplit? Function()? split,
  }) => GeneratorQuestionsState(
    step: step ?? this.step,
    goal: goal ?? this.goal,
    level: level ?? this.level,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    sessionMinutes: sessionMinutes ?? this.sessionMinutes,
    equipment: equipment ?? this.equipment,
    focus: focus ?? this.focus,
    excluded: excluded ?? this.excluded,
    easyArea: easyArea != null ? easyArea() : this.easyArea,
    split: split != null ? split() : this.split,
  );

  @override
  List<Object?> get props => [
    step,
    goal,
    level,
    daysPerWeek,
    sessionMinutes,
    equipment,
    focus,
    excluded,
    easyArea,
    split,
  ];
}

/// The generator's questions, one at a time, prefilled from what the user
/// already answered in onboarding.
class GeneratorQuestionsCubit extends Cubit<GeneratorQuestionsState> {
  GeneratorQuestionsCubit(GeneratorPrefill prefill)
    : super(
        GeneratorQuestionsState(
          goal: prefill.goal,
          level: prefill.level,
          daysPerWeek: switch (prefill.daysPerWeek) {
            final days?
                when days >= GeneratorLimits.minDays &&
                    days <= GeneratorLimits.maxDays =>
              days,
            _ => null,
          },
          equipment: prefill.equipment?.difference({Equipment.bodyweight}),
        ),
      );

  /// To the next question, once this one is answered.
  void next() {
    if (!state.answered || state.isLast) return;
    emit(state.copyWith(step: GeneratorStep.values[state.step.index + 1]));
  }

  /// To the previous question; false on the first one.
  bool back() {
    if (state.step.index == 0) return false;
    emit(state.copyWith(step: GeneratorStep.values[state.step.index - 1]));
    return true;
  }

  void setGoal(Goal goal) => emit(state.copyWith(goal: goal));

  void setLevel(Level level) => emit(state.copyWith(level: level));

  void setDays(int days) => emit(state.copyWith(daysPerWeek: days));

  void setSessionMinutes(int minutes) =>
      emit(state.copyWith(sessionMinutes: minutes));

  void applyPreset(EquipmentProfile profile) =>
      emit(state.copyWith(equipment: profile.equipment));

  void toggleEquipment(Equipment item) {
    final owned = state.equipment ?? const <Equipment>{};
    emit(
      state.copyWith(
        equipment: owned.contains(item)
            ? owned.difference({item})
            : {...owned, item},
      ),
    );
  }

  /// Up to [GeneratorLimits.maxFocusMuscles]; never a muscle of the area to
  /// go easy on.
  void toggleFocus(Muscle muscle) {
    final focus = state.focus;
    if (focus.contains(muscle)) {
      emit(state.copyWith(focus: focus.difference({muscle})));
    } else if (focus.length < GeneratorLimits.maxFocusMuscles &&
        !(state.easyArea?.muscles.contains(muscle) ?? false)) {
      emit(state.copyWith(focus: {...focus, muscle}));
    }
  }

  void exclude(Iterable<String> exerciseIds) =>
      emit(state.copyWith(excluded: {...state.excluded, ...exerciseIds}));

  void include(String exerciseId) =>
      emit(state.copyWith(excluded: state.excluded.difference({exerciseId})));

  /// Null for none. Focus muscles of the area are dropped: it wins.
  void setEasyArea(EasyArea? area) => emit(
    state.copyWith(
      easyArea: () => area,
      focus: area == null ? null : state.focus.difference(area.muscles),
    ),
  );

  /// Null for the one that suits the days best.
  void setSplit(TrainingSplit? split) =>
      emit(state.copyWith(split: () => split));
}
