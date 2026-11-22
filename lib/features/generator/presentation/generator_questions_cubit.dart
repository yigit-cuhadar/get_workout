import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/generator_answers.dart';
import '../domain/generator_options.dart';
import '../domain/generator_usecases.dart';

/// The pages of the questions, in order; [style] and [split] show only
/// when they have something to ask ([GeneratorQuestionsState.steps]).
enum GeneratorStep { profile, session, focus, skip, sensitive, style, split }

enum OptionsStatus {
  loading,
  ready,

  /// Offline, and the options were never loaded on this device.
  offline,

  /// Nothing is published yet.
  unavailable,
  failure,
}

/// What the user already told the app; each prefills its answer.
typedef GeneratorPrefill = ({
  Goal? goal,
  Level? level,
  int? daysPerWeek,
  Set<Equipment>? equipment,
});

class GeneratorQuestionsState extends Equatable {
  const GeneratorQuestionsState({
    this.status = OptionsStatus.loading,
    this.options,
    this.step = GeneratorStep.profile,
    this.goal,
    this.level,
    this.daysPerWeek,
    this.equipment,
    this.sessionMinutes,
    this.focus = const {},
    this.skip = const {},
    this.sensitive = const {},
    this.equipmentStyle = EquipmentStyle.any,
    this.splitId,
  });

  final OptionsStatus status;

  /// Once loaded; kept when a later read fails.
  final GeneratorOptions? options;
  final GeneratorStep step;
  final Goal? goal;
  final Level? level;
  final int? daysPerWeek;

  /// Never holds [Equipment.bodyweight]; empty is bodyweight only.
  final Set<Equipment>? equipment;

  /// Null until the options are loaded.
  final int? sessionMinutes;
  final Set<FocusArea> focus;
  final Set<FocusArea> skip;
  final Set<SensitiveArea> sensitive;

  /// The style picked; it counts only while [styleApplies].
  final EquipmentStyle equipmentStyle;

  /// The split picked, null for "Let the app choose"; it counts only while
  /// it fits.
  final String? splitId;

  bool get profileAnswered =>
      goal != null && level != null && daysPerWeek != null && equipment != null;

  bool get styleApplies => equipmentStyleApplies(equipment ?? const {});

  /// The splits the split question offers for the profile answers.
  List<GeneratorSplit> get fittingSplits {
    final options = this.options;
    if (options == null || !profileAnswered) return const [];
    return options.splitsFitting(daysPerWeek!, level!, goal!);
  }

  /// The pages that show, in order.
  List<GeneratorStep> get steps => [
    GeneratorStep.profile,
    GeneratorStep.session,
    GeneratorStep.focus,
    GeneratorStep.skip,
    GeneratorStep.sensitive,
    if (styleApplies) GeneratorStep.style,
    if (fittingSplits.length > 1) GeneratorStep.split,
  ];

  bool get isLast => step == steps.last;

  /// Whether the page on screen is answered; only the profile can be
  /// unanswered, the others start with an answer.
  bool get answered => step != GeneratorStep.profile || profileAnswered;

  /// Null until the options are loaded and the profile is answered.
  GeneratorAnswers? get answers {
    final minutes = sessionMinutes;
    if (!profileAnswered || minutes == null) return null;
    final split = splitId;
    final splits = fittingSplits;
    return GeneratorAnswers(
      goal: goal!,
      level: level!,
      daysPerWeek: daysPerWeek!,
      sessionMinutes: minutes,
      equipment: equipment!,
      focus: focus,
      skip: skip,
      sensitive: sensitive,
      equipmentStyle: styleApplies ? equipmentStyle : EquipmentStyle.any,
      splitId: splits.length > 1 && splits.any((s) => s.id == split)
          ? split
          : null,
    );
  }

  GeneratorQuestionsState copyWith({
    OptionsStatus? status,
    GeneratorOptions? options,
    GeneratorStep? step,
    Goal? goal,
    Level? level,
    int? daysPerWeek,
    Set<Equipment>? equipment,
    int? sessionMinutes,
    Set<FocusArea>? focus,
    Set<FocusArea>? skip,
    Set<SensitiveArea>? sensitive,
    EquipmentStyle? equipmentStyle,
    String? Function()? splitId,
  }) => GeneratorQuestionsState(
    status: status ?? this.status,
    options: options ?? this.options,
    step: step ?? this.step,
    goal: goal ?? this.goal,
    level: level ?? this.level,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    equipment: equipment ?? this.equipment,
    sessionMinutes: sessionMinutes ?? this.sessionMinutes,
    focus: focus ?? this.focus,
    skip: skip ?? this.skip,
    sensitive: sensitive ?? this.sensitive,
    equipmentStyle: equipmentStyle ?? this.equipmentStyle,
    splitId: splitId != null ? splitId() : this.splitId,
  );

  @override
  List<Object?> get props => [
    status,
    options,
    step,
    goal,
    level,
    daysPerWeek,
    equipment,
    sessionMinutes,
    focus,
    skip,
    sensitive,
    equipmentStyle,
    splitId,
  ];
}

/// The generator's questions, a page at a time, over what the server
/// offers; the profile answers are prefilled and changed for this program
/// only.
class GeneratorQuestionsCubit extends Cubit<GeneratorQuestionsState> {
  GeneratorQuestionsCubit(
    GeneratorPrefill prefill, {
    required this._watchOptions,
  }) : super(_prefilled(const GeneratorQuestionsState(), prefill)) {
    _listen();
  }

  final WatchGeneratorOptions _watchOptions;
  StreamSubscription<GeneratorOptions>? _subscription;

  /// [state] with the profile answers it lacks taken from [prefill]; days
  /// out of the generator's range stay unanswered.
  static GeneratorQuestionsState _prefilled(
    GeneratorQuestionsState state,
    GeneratorPrefill prefill,
  ) => state.copyWith(
    goal: state.goal ?? prefill.goal,
    level: state.level ?? prefill.level,
    daysPerWeek:
        state.daysPerWeek ??
        switch (prefill.daysPerWeek) {
          final days? when ProfileLimits.daysPerWeek(days) => days,
          _ => null,
        },
    equipment:
        state.equipment ??
        prefill.equipment?.difference(const {Equipment.bodyweight}),
  );

  void _listen() {
    _subscription = _watchOptions().listen(
      _onOptions,
      onError: (Object error) {
        // Options already loaded still answer every question.
        if (state.options != null) return;
        emit(
          state.copyWith(
            status: switch (error) {
              NetworkFailure() => OptionsStatus.offline,
              NotFoundFailure() => OptionsStatus.unavailable,
              _ => OptionsStatus.failure,
            },
          ),
        );
      },
    );
  }

  /// Keeps the answers the new [options] still offer.
  void _onOptions(GeneratorOptions options) {
    final minutes = state.sessionMinutes;
    emit(
      state.copyWith(
        status: OptionsStatus.ready,
        options: options,
        sessionMinutes:
            minutes != null && options.sessionMinutes.contains(minutes)
            ? minutes
            : options.defaultSessionMinutes,
        focus: _first(state.focus, options.maxFocusAreas),
        skip: _first(state.skip, options.maxSkipAreas),
      ),
    );
  }

  static Set<FocusArea> _first(Set<FocusArea> areas, int max) =>
      areas.length <= max ? areas : areas.take(max).toSet();

  /// Reads the options again after they failed to load.
  void retry() {
    unawaited(_subscription?.cancel());
    emit(state.copyWith(status: OptionsStatus.loading));
    _listen();
  }

  /// Fills the profile answers not given yet, e.g. once the profile has
  /// loaded.
  void prefill(GeneratorPrefill prefill) => emit(_prefilled(state, prefill));

  /// The profile answers of [answers] for this program, from a question
  /// opened on the first page.
  void changeProfile(UserProfile answers) => emit(
    state.copyWith(
      goal: answers.goal,
      level: answers.level,
      daysPerWeek: answers.daysPerWeek,
      equipment: answers.equipment?.difference(const {Equipment.bodyweight}),
    ),
  );

  /// To the next page, once this one is answered.
  void next() {
    final steps = state.steps;
    if (!state.answered || state.isLast) return;
    emit(state.copyWith(step: steps[steps.indexOf(state.step) + 1]));
  }

  /// To the previous page; false on the first one.
  bool back() {
    final steps = state.steps;
    final index = steps.indexOf(state.step);
    if (index <= 0) return false;
    emit(state.copyWith(step: steps[index - 1]));
    return true;
  }

  void setSessionMinutes(int minutes) =>
      emit(state.copyWith(sessionMinutes: minutes));

  /// Adds [area] to the focus areas up to the most allowed, taking it out
  /// of those left out, or removes it.
  void toggleFocus(FocusArea area) {
    final focus = state.focus;
    if (focus.contains(area)) {
      return emit(state.copyWith(focus: focus.difference({area})));
    }
    if (focus.length >= (state.options?.maxFocusAreas ?? 0)) return;
    emit(
      state.copyWith(
        focus: {...focus, area},
        skip: state.skip.difference({area}),
      ),
    );
  }

  /// Adds [area] to those left out up to the most allowed, or removes it;
  /// a focus area cannot be left out.
  void toggleSkip(FocusArea area) {
    final skip = state.skip;
    if (skip.contains(area)) {
      return emit(state.copyWith(skip: skip.difference({area})));
    }
    if (state.focus.contains(area) ||
        skip.length >= (state.options?.maxSkipAreas ?? 0)) {
      return;
    }
    emit(state.copyWith(skip: {...skip, area}));
  }

  /// "No sensitive areas".
  void clearSensitive() => emit(state.copyWith(sensitive: const {}));

  void toggleSensitive(SensitiveArea area) {
    final sensitive = state.sensitive;
    emit(
      state.copyWith(
        sensitive: sensitive.contains(area)
            ? sensitive.difference({area})
            : {...sensitive, area},
      ),
    );
  }

  void setEquipmentStyle(EquipmentStyle style) =>
      emit(state.copyWith(equipmentStyle: style));

  /// Null for "Let the app choose".
  void setSplit(String? splitId) =>
      emit(state.copyWith(splitId: () => splitId));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
