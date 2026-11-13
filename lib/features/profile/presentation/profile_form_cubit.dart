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
    this.welcome = false,
    this.step = 0,
    this.status = ProfileFormStatus.editing,
    this.failure,
  });

  /// Asked one per step, in this order.
  final List<ProfileField> questions;

  /// A welcome, then all questions; otherwise one question being edited.
  final bool onboarding;

  /// Onboarding shows its welcome instead of a question.
  final bool welcome;

  /// Index into [questions].
  final int step;

  /// Only valid answers, always metric.
  final UserProfile answers;
  final ProfileFormStatus status;

  /// Set when saving failed; the answers stay for another try.
  final Failure? failure;

  ProfileField get question => questions[step];

  bool get last => step == questions.length - 1;

  bool get canContinue => welcome || answers.answered(question);

  ProfileFormState copyWith({
    bool? welcome,
    int? step,
    UserProfile? answers,
    ProfileFormStatus? status,
    Failure? failure,
  }) => ProfileFormState(
    questions: questions,
    onboarding: onboarding,
    welcome: welcome ?? this.welcome,
    step: step ?? this.step,
    answers: answers ?? this.answers,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    questions,
    onboarding,
    welcome,
    step,
    answers,
    status,
    failure,
  ];
}

/// The profile questions as a form. Onboarding opens with a welcome and
/// asks all of them; editing asks one and saves it alone.
///
/// A number question is answered as soon as it shows: its ruler or wheel
/// has to start somewhere, and a user already there just moves on.
class ProfileFormCubit extends Cubit<ProfileFormState> {
  /// The welcome, then every question. Next on the last one completes
  /// onboarding with the answers.
  ProfileFormCubit.onboarding({
    required String uid,
    required UserProfile initial,
    required CompleteOnboarding completeOnboarding,
    this._now = DateTime.now,
  }) : _save = ((answers) => completeOnboarding((uid: uid, answers: answers))),
       _storedBirthYear = initial.birthYear,
       _targetSet = initial.answered(ProfileField.targetWeight),
       super(
         ProfileFormState(
           questions: ProfileField.values,
           answers: initial,
           onboarding: true,
           welcome: true,
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
       _storedBirthYear = initial.birthYear,
       _targetSet = initial.answered(ProfileField.targetWeight),
       super(
         ProfileFormState(
           questions: [field],
           answers: initial,
           onboarding: false,
         ),
       ) {
    _prefill();
  }

  final DateTime Function() _now;
  final Future<Result<void>> Function(UserProfile answers)? _save;

  /// The year already given, kept selectable when it has since left the
  /// plausible range, so the wheel never shows one year and saves another.
  final int? _storedBirthYear;

  /// Whether the target weight is the user's own; until then it follows
  /// the body weight.
  bool _targetSet;

  /// Where the rulers and the wheel start without an answer.
  static const _startHeightCm = 170.0;
  static const _startWeightKg = 70.0;
  static const _startAge = 30;

  /// The birth years [setBirthYear] accepts: those plausible this year and
  /// the one already given.
  ({int min, int max}) get birthYearRange {
    final year = _now().year;
    final min = year - ProfileLimits.maxAge;
    final max = year - ProfileLimits.minAge;
    final stored = _storedBirthYear;
    if (stored == null) return (min: min, max: max);
    return (min: stored < min ? stored : min, max: stored > max ? stored : max);
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

  /// Ignores a year outside [birthYearRange].
  void setBirthYear(int year) {
    if (year == _storedBirthYear ||
        ProfileLimits.birthYear(year, currentYear: _now().year)) {
      _answer(state.answers.copyWith(birthYear: year));
    }
  }

  /// Whether [value] in [unit] is a valid height; only then is it the
  /// answer. Likewise for the weights below.
  bool setHeight(double value, LengthUnit unit) {
    final cm = unit.toCm(value);
    if (!ProfileLimits.heightCm(cm)) return false;
    _answer(state.answers.copyWith(heightCm: cm));
    return true;
  }

  bool setWeight(double value, WeightUnit unit) {
    final kg = unit.toKg(value);
    if (!ProfileLimits.weightKg(kg)) return false;
    _answer(state.answers.copyWith(weightKg: kg));
    return true;
  }

  bool setTargetWeight(double value, WeightUnit unit) {
    final kg = unit.toKg(value);
    if (!ProfileLimits.weightKg(kg)) return false;
    _targetSet = true;
    _answer(state.answers.copyWith(targetWeightKg: kg));
    return true;
  }

  /// Typed entries: whether [text] is a valid answer, which it then is.
  bool enterHeight(String text, LengthUnit unit) =>
      _enter(text, (value) => setHeight(value, unit));

  bool enterWeight(String text, WeightUnit unit) =>
      _enter(text, (value) => setWeight(value, unit));

  bool enterTargetWeight(String text, WeightUnit unit) =>
      _enter(text, (value) => setTargetWeight(value, unit));

  /// From the welcome to the first question.
  void start() {
    if (state.welcome) _show(step: 0);
  }

  /// To the next question or, on the last one, saves.
  Future<void> next() async {
    if (state.status != ProfileFormStatus.editing ||
        state.welcome ||
        !state.canContinue) {
      return;
    }
    if (!state.last) return _show(step: state.step + 1);
    await _submit();
  }

  /// To the previous question, or from the first one to the welcome.
  void back() {
    if (state.status != ProfileFormStatus.editing || state.welcome) return;
    if (state.step > 0) {
      emit(state.copyWith(step: state.step - 1));
    } else if (state.onboarding) {
      emit(state.copyWith(welcome: true));
    }
  }

  void _show({required int step}) {
    emit(state.copyWith(welcome: false, step: step));
    _prefill();
  }

  /// Answers a number question that shows unanswered with where its input
  /// starts. A target weight the user has not set is the body weight, as
  /// it is now: keeping it.
  void _prefill() {
    final answers = state.answers;
    if (state.question == ProfileField.targetWeight && !_targetSet) {
      return _answer(
        answers.copyWith(targetWeightKg: answers.weightKg ?? _startWeightKg),
      );
    }
    if (answers.answered(state.question)) return;
    switch (state.question) {
      case ProfileField.birthYear:
        _answer(answers.copyWith(birthYear: _now().year - _startAge));
      case ProfileField.height:
        _answer(answers.copyWith(heightCm: _startHeightCm));
      case ProfileField.weight:
        _answer(answers.copyWith(weightKg: _startWeightKg));
      case ProfileField.goal ||
          ProfileField.targetWeight ||
          ProfileField.level ||
          ProfileField.daysPerWeek ||
          ProfileField.equipment ||
          ProfileField.sex:
        break;
    }
  }

  Future<void> _submit() async {
    emit(state.copyWith(status: ProfileFormStatus.submitted));
    final save = _save;
    if (save == null) return;
    final failure = (await save(state.answers)).failureOrNull;
    if (failure != null && !isClosed) {
      emit(state.copyWith(status: ProfileFormStatus.editing, failure: failure));
    }
  }

  void _answer(UserProfile answers) => emit(state.copyWith(answers: answers));

  bool _enter(String text, bool Function(double value) accept) {
    final value = _parse(text);
    return value != null && accept(value);
  }

  /// Far beyond every limit, far below where conversions lose meaning.
  static const _absurd = 1e6;

  /// Null when not a plain number: empty, "Infinity", "NaN", overflowing
  /// exponents and digit strings.
  static double? _parse(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value.abs() > _absurd) return null;
    return value;
  }
}
