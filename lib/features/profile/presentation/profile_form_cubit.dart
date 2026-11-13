import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/profile_usecases.dart';
import '../domain/user_profile.dart';

enum ProfileFormStatus {
  editing,

  /// The answers were handed to the repository. Firestore applies them to
  /// its local cache at once, so the page moves on without waiting for the
  /// server, which never answers while offline.
  submitted,
}

class ProfileFormState extends Equatable {
  const ProfileFormState({
    required this.questions,
    required this.answers,
    required this.onboarding,
    this.step = 0,
    this.invalid = const {},
    this.status = ProfileFormStatus.editing,
    this.failure,
  });

  /// Asked one per step, in this order.
  final List<ProfileField> questions;

  /// All questions and a summary; otherwise one question being edited.
  final bool onboarding;

  /// Index into [questions]; [questions].length is the closing summary.
  final int step;

  /// Only valid answers, always metric.
  final UserProfile answers;

  /// Questions whose entry is not a valid answer; they have none in
  /// [answers] and block moving on.
  final Set<ProfileField> invalid;
  final ProfileFormStatus status;

  /// Set when saving failed; the answers stay for another try.
  final Failure? failure;

  /// Null on the summary.
  ProfileField? get question =>
      step < questions.length ? questions[step] : null;

  bool get canContinue {
    final question = this.question;
    if (question == null) return true;
    if (invalid.contains(question)) return false;
    // Onboarding skips a personal question with [ProfileFormCubit.skipQuestion]
    // instead; editing saves an empty one as cleared.
    return answers.answered(question) || (!onboarding && question.optional);
  }

  bool get canSkipQuestion => onboarding && (question?.optional ?? false);

  ProfileFormState copyWith({
    int? step,
    UserProfile? answers,
    Set<ProfileField>? invalid,
    ProfileFormStatus? status,
    Failure? failure,
  }) => ProfileFormState(
    questions: questions,
    onboarding: onboarding,
    step: step ?? this.step,
    answers: answers ?? this.answers,
    invalid: invalid ?? this.invalid,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    questions,
    onboarding,
    step,
    answers,
    invalid,
    status,
    failure,
  ];
}

/// Who last ended onboarding with "Skip for now" in this run of the app.
/// The router then lands them on Today instead of suggesting a program.
/// Not stored: at the next start a completed profile goes to Today anyway.
class SkippedOnboarding {
  String? uid;
}

/// The profile questions as a form, in the user's units. Onboarding asks all
/// of them and closes with a summary; editing asks one and saves it alone.
class ProfileFormCubit extends Cubit<ProfileFormState> {
  /// Every question, then the summary. Finishing or skipping completes
  /// onboarding with whatever was answered; skipping is recorded in
  /// [skipped].
  ProfileFormCubit.onboarding({
    required String uid,
    required UserProfile initial,
    required CompleteOnboarding completeOnboarding,
    required SkippedOnboarding skipped,
    this._now = DateTime.now,
  }) : _save = ((answers) => completeOnboarding((uid: uid, answers: answers))),
       _markSkipped = ((skip) => skipped.uid = skip ? uid : null),
       super(
         ProfileFormState(
           questions: ProfileField.values,
           answers: initial,
           onboarding: true,
         ),
       );

  /// The one question [field]. Finishing only marks the answer submitted;
  /// the page hands it to the app-wide `ProfileCubit`, which outlives the
  /// page and reports a late rejection.
  ProfileFormCubit.edit({
    required ProfileField field,
    required UserProfile initial,
    this._now = DateTime.now,
  }) : _save = null,
       _markSkipped = null,
       super(
         ProfileFormState(
           questions: [field],
           answers: initial,
           onboarding: false,
         ),
       );

  final DateTime Function() _now;
  final Future<Result<void>> Function(UserProfile answers)? _save;
  final void Function(bool skipped)? _markSkipped;

  /// The birth years [enterBirthYear] accepts this year.
  ({int min, int max}) get birthYearRange {
    final year = _now().year;
    return (min: year - ProfileLimits.maxAge, max: year - ProfileLimits.minAge);
  }

  void setGoal(Goal goal) => _answer(state.answers.copyWith(goal: goal));

  void setLevel(Level level) => _answer(state.answers.copyWith(level: level));

  void setDaysPerWeek(int days) {
    if (ProfileLimits.daysPerWeek(days)) {
      _answer(state.answers.copyWith(daysPerWeek: days));
    }
  }

  void setSex(Sex sex) => _answer(state.answers.copyWith(sex: sex));

  void applyPreset(EquipmentProfile preset) =>
      _answer(state.answers.copyWith(equipment: preset.equipment));

  void toggleEquipment(Equipment item) {
    final owned = {...?state.answers.equipment};
    if (!owned.remove(item)) owned.add(item);
    _answer(state.answers.copyWith(equipment: owned));
  }

  void enterBirthYear(String text) => _enter(
    ProfileField.birthYear,
    _parse(text),
    (year) =>
        year == year.roundToDouble() &&
            ProfileLimits.birthYear(year.toInt(), currentYear: _now().year)
        ? state.answers.copyWith(birthYear: year.toInt())
        : null,
  );

  void enterHeight(String text, LengthUnit unit) =>
      _enter(ProfileField.height, _parse(text), (value) {
        final cm = unit.toCm(value);
        return ProfileLimits.heightCm(cm)
            ? state.answers.copyWith(heightCm: cm)
            : null;
      });

  void enterWeight(String text, WeightUnit unit) =>
      _enter(ProfileField.weight, _parse(text), (value) {
        final kg = unit.toKg(value);
        return ProfileLimits.weightKg(kg)
            ? state.answers.copyWith(weightKg: kg)
            : null;
      });

  void enterTargetWeight(String text, WeightUnit unit) =>
      _enter(ProfileField.targetWeight, _parse(text), (value) {
        final kg = unit.toKg(value);
        return ProfileLimits.weightKg(kg)
            ? state.answers.copyWith(targetWeightKg: kg)
            : null;
      });

  /// The unit of [field] changed and its entry restarts from the answer,
  /// shown in the new unit; an invalid entry is dropped.
  void unitChanged(ProfileField field) {
    if (state.invalid.contains(field)) {
      emit(state.copyWith(invalid: {...state.invalid}..remove(field)));
    }
  }

  /// To the next question, to the summary after the last one, or, without
  /// a summary, saves.
  Future<void> next() async {
    if (state.status != ProfileFormStatus.editing || !state.canContinue) {
      return;
    }
    final last = state.onboarding
        ? state.questions.length
        : state.questions.length - 1;
    if (state.step < last) return emit(state.copyWith(step: state.step + 1));
    await _submit();
  }

  void back() {
    if (state.step > 0 && state.status == ProfileFormStatus.editing) {
      emit(state.copyWith(step: state.step - 1));
    }
  }

  /// Ends onboarding now with the answers given so far.
  Future<void> skip() async {
    if (state.onboarding && state.status == ProfileFormStatus.editing) {
      await _submit(skipped: true);
    }
  }

  /// Leaves a personal question unanswered and moves on.
  void skipQuestion() {
    final question = state.question;
    if (!state.canSkipQuestion ||
        question == null ||
        state.status != ProfileFormStatus.editing) {
      return;
    }
    emit(
      state.copyWith(
        step: state.step + 1,
        answers: state.answers.without(question),
        invalid: {...state.invalid}..remove(question),
      ),
    );
  }

  Future<void> _submit({bool skipped = false}) async {
    // Before saving: the completed profile reaches the router from
    // Firestore's local cache before the save returns, or never returns
    // while offline.
    _markSkipped?.call(skipped);
    emit(state.copyWith(status: ProfileFormStatus.submitted));
    final save = _save;
    if (save == null) return;
    final failure = (await save(state.answers)).failureOrNull;
    if (failure != null && !isClosed) {
      emit(state.copyWith(status: ProfileFormStatus.editing, failure: failure));
    }
  }

  void _answer(UserProfile answers) => emit(state.copyWith(answers: answers));

  /// [value] is null for an empty entry, NaN for one that is not a number.
  /// [accept] gives the answers with a valid value, or null.
  void _enter(
    ProfileField field,
    double? value,
    UserProfile? Function(double value) accept,
  ) {
    final accepted = value == null || value.isNaN ? null : accept(value);
    final invalid = {...state.invalid}..remove(field);
    if (value != null && accepted == null) invalid.add(field);
    emit(
      state.copyWith(
        answers: accepted ?? state.answers.without(field),
        invalid: invalid,
      ),
    );
  }

  /// Far beyond every limit, far below where conversions lose meaning.
  static const _absurd = 1e6;

  /// Null when empty; NaN, which every limit rejects, when not a plain
  /// number: "Infinity", "NaN", overflowing exponents and digit strings.
  static double? _parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final value = double.tryParse(trimmed.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value.abs() > _absurd) {
      return double.nan;
    }
    return value;
  }
}
