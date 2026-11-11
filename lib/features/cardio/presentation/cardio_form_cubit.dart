import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';
import '../domain/cardio_usecases.dart';
import '../domain/cardio_validation.dart';
import 'cardio_text.dart';

enum CardioFormStatus {
  editing,
  saving,
  saved,
  saveFailed,
  deleting,
  deleted,
  deleteFailed,
}

/// The form's inputs. Number fields hold the text as typed, distance in the
/// unit the user sees.
class CardioFormState extends Equatable {
  const CardioFormState({
    required this.type,
    required this.date,
    this.duration = Duration.zero,
    this.distance = '',
    this.calories = '',
    this.heartRate = '',
    this.incline = '',
    this.note = '',
    this.issues = const {},
    this.status = CardioFormStatus.editing,
    this.failure,
  });

  final CardioType type;
  final DateTime date;
  final Duration duration;
  final String distance;
  final String calories;
  final String heartRate;
  final String incline;
  final String note;

  /// Shown once a save was attempted, then kept up to date.
  final Set<CardioIssue> issues;
  final CardioFormStatus status;
  final Failure? failure;

  bool get isBusy =>
      status == CardioFormStatus.saving || status == CardioFormStatus.deleting;

  CardioFormState copyWith({
    CardioType? type,
    DateTime? date,
    Duration? duration,
    String? distance,
    String? calories,
    String? heartRate,
    String? incline,
    String? note,
    Set<CardioIssue>? issues,
    CardioFormStatus? status,
    Failure? failure,
  }) => CardioFormState(
    type: type ?? this.type,
    date: date ?? this.date,
    duration: duration ?? this.duration,
    distance: distance ?? this.distance,
    calories: calories ?? this.calories,
    heartRate: heartRate ?? this.heartRate,
    incline: incline ?? this.incline,
    note: note ?? this.note,
    issues: issues ?? this.issues,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    type,
    date,
    duration,
    distance,
    calories,
    heartRate,
    incline,
    note,
    issues,
    status,
    failure,
  ];
}

/// Logs a new session, or edits [initial]. Distances are typed and shown in
/// [unit] and converted to km only here.
class CardioFormCubit extends Cubit<CardioFormState> {
  CardioFormCubit({
    required this._saveSession,
    required this._deleteSession,
    required GetCurrentUser getCurrentUser,
    required this._unit,
    this._initial,
    DateTime Function()? clock,
  }) : _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(_initialState(_initial, _unit, clock ?? DateTime.now));

  final SaveCardioSession _saveSession;
  final DeleteCardioSession _deleteSession;
  final GetCurrentUser _getCurrentUser;
  final DistanceUnit _unit;
  final CardioSession? _initial;
  final DateTime Function() _clock;

  /// The user the form was opened for; it never writes for anyone else.
  final String? _uid;
  bool _submitted = false;

  bool get isEditing => _initial?.id != null;

  static CardioFormState _initialState(
    CardioSession? session,
    DistanceUnit unit,
    DateTime Function() clock,
  ) {
    if (session == null) {
      final now = clock();
      return CardioFormState(
        type: CardioType.outdoorRun,
        date: DateTime(now.year, now.month, now.day, now.hour, now.minute),
      );
    }
    return CardioFormState(
      type: session.type,
      date: session.date,
      duration: session.duration,
      distance: _distanceText(session.distanceKm, unit),
      calories: session.calories?.toString() ?? '',
      heartRate: session.avgHeartRate?.toString() ?? '',
      incline: session.incline == null
          ? ''
          : formatDecimal(session.incline!, 1),
      note: session.note ?? '',
    );
  }

  void setType(CardioType type) => _change(state.copyWith(type: type));
  void setDate(DateTime date) => _change(state.copyWith(date: date));
  void setDuration(Duration duration) =>
      _change(state.copyWith(duration: duration));
  void setDistance(String text) => _change(state.copyWith(distance: text));
  void setCalories(String text) => _change(state.copyWith(calories: text));
  void setHeartRate(String text) => _change(state.copyWith(heartRate: text));
  void setIncline(String text) => _change(state.copyWith(incline: text));
  void setNote(String text) => _change(state.copyWith(note: text));

  void _change(CardioFormState next) {
    final editing = next.copyWith(status: CardioFormStatus.editing);
    emit(_submitted ? editing.copyWith(issues: _check(editing).$2) : editing);
  }

  Future<void> save() async {
    if (state.isBusy) return;
    _submitted = true;
    final (session, issues) = _check(state);
    if (issues.isNotEmpty) {
      emit(state.copyWith(issues: issues, status: CardioFormStatus.editing));
      return;
    }
    await _run(
      CardioFormStatus.saving,
      CardioFormStatus.saved,
      CardioFormStatus.saveFailed,
      (uid) => _saveSession((uid: uid, session: session)),
    );
  }

  Future<void> delete() async {
    final id = _initial?.id;
    if (id == null || state.isBusy) return;
    await _run(
      CardioFormStatus.deleting,
      CardioFormStatus.deleted,
      CardioFormStatus.deleteFailed,
      (uid) => _deleteSession((uid: uid, id: id)),
    );
  }

  Future<void> _run(
    CardioFormStatus busy,
    CardioFormStatus done,
    CardioFormStatus failed,
    Future<Result<void>> Function(String uid) action,
  ) async {
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) {
      emit(
        state.copyWith(
          status: failed,
          failure: const PermissionFailure('Signed-in user changed'),
        ),
      );
      return;
    }
    emit(state.copyWith(status: busy, issues: const {}));
    final failure = (await action(uid)).failureOrNull;
    if (isClosed) return;
    emit(
      failure == null
          ? state.copyWith(status: done)
          : state.copyWith(status: failed, failure: failure),
    );
  }

  /// The session the inputs describe, and what is wrong with it. Fields the
  /// type does not use are left out.
  (CardioSession, Set<CardioIssue>) _check(CardioFormState input) {
    final type = input.type;
    final unreadable = <CardioIssue>{};

    T? read<T extends num>(
      bool used,
      String text,
      T? Function(String) parse,
      CardioIssue issue,
    ) {
      final trimmed = text.trim().replaceAll(',', '.');
      if (!used || trimmed.isEmpty) return null;
      final value = parse(trimmed);
      if (value == null) unreadable.add(issue);
      return value;
    }

    final distance = read(
      type.distance,
      input.distance,
      double.tryParse,
      CardioIssue.distanceOutOfRange,
    );
    final note = input.note.trim();
    final session = CardioSession(
      id: _initial?.id,
      type: type,
      date: input.date,
      duration: input.duration,
      distanceKm: _distanceKm(input.distance, distance),
      calories: read(
        true,
        input.calories,
        int.tryParse,
        CardioIssue.caloriesOutOfRange,
      ),
      avgHeartRate: read(
        true,
        input.heartRate,
        int.tryParse,
        CardioIssue.heartRateOutOfRange,
      ),
      incline: read(
        type.incline,
        input.incline,
        double.tryParse,
        CardioIssue.inclineOutOfRange,
      ),
      note: note.isEmpty ? null : note,
    );
    return (
      session,
      {...unreadable, ...validateCardio(session, now: _clock())},
    );
  }

  /// Keeps the stored km when the shown, rounded distance was not edited, so
  /// saving other changes does not drift it.
  double? _distanceKm(String text, double? value) {
    if (value == null) return null;
    final initial = _initial?.distanceKm;
    if (initial != null && text == _distanceText(initial, _unit)) {
      return initial;
    }
    return _unit.toKm(value);
  }

  static String _distanceText(double? km, DistanceUnit unit) =>
      km == null ? '' : formatDecimal(unit.fromKm(km), 2);
}
