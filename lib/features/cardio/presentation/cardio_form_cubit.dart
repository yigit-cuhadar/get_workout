import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';
import '../domain/cardio_usecases.dart';
import '../domain/cardio_validation.dart';

enum CardioFormStatus {
  editing,
  saving,
  saved,
  saveFailed,
  deleting,
  deleted,
  deleteFailed,

  /// The signed-in user changed; the form must close.
  closed,
}

/// The form's values as picked; distance in the unit the user sees.
class CardioFormState extends Equatable {
  const CardioFormState({
    required this.type,
    required this.date,
    this.duration = Duration.zero,
    this.distance,
    this.calories,
    this.heartRate,
    this.incline,
    this.note = '',
    this.issues = const {},
    this.status = CardioFormStatus.editing,
    this.failure,
  });

  final CardioType type;
  final DateTime date;
  final Duration duration;
  final double? distance;
  final int? calories;
  final int? heartRate;
  final double? incline;
  final String note;

  /// Shown once a save was attempted, then kept up to date.
  final Set<CardioIssue> issues;
  final CardioFormStatus status;
  final Failure? failure;

  bool get isBusy =>
      status == CardioFormStatus.saving || status == CardioFormStatus.deleting;

  /// Save is off until there is a duration, the one required value (CL06).
  bool get canSave => duration > Duration.zero && !isBusy;

  CardioFormState copyWith({
    CardioType? type,
    DateTime? date,
    Duration? duration,
    double? Function()? distance,
    int? Function()? calories,
    int? Function()? heartRate,
    double? Function()? incline,
    String? note,
    Set<CardioIssue>? issues,
    CardioFormStatus? status,
    Failure? failure,
  }) => CardioFormState(
    type: type ?? this.type,
    date: date ?? this.date,
    duration: duration ?? this.duration,
    distance: distance == null ? this.distance : distance(),
    calories: calories == null ? this.calories : calories(),
    heartRate: heartRate == null ? this.heartRate : heartRate(),
    incline: incline == null ? this.incline : incline(),
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

/// Logs a new session, or edits [initial]. Distances are picked and shown in
/// [unit] and converted to km only here. Closes when the signed-in user
/// changes, so it never shows or writes another user's session.
class CardioFormCubit extends Cubit<CardioFormState> {
  CardioFormCubit({
    required this._saveSession,
    required this._deleteSession,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required this._unit,
    required this._analytics,
    this._initial,
    DateTime Function()? clock,
  }) : _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(_initialState(_initial, _unit, clock ?? DateTime.now)) {
    _start = state;
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid && state.status != CardioFormStatus.closed) {
            emit(state.copyWith(status: CardioFormStatus.closed));
          }
        });
  }

  final SaveCardioSession _saveSession;
  final Analytics _analytics;
  final DeleteCardioSession _deleteSession;
  final GetCurrentUser _getCurrentUser;
  final DistanceUnit _unit;
  final CardioSession? _initial;
  final DateTime Function() _clock;

  /// The user the form was opened for.
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;
  bool _submitted = false;

  bool get isEditing => _initial?.id != null;

  /// What [hasChanges] compares against.
  late final CardioFormState _start;

  /// A value differs from those the form opened with; nothing once it
  /// saved or closed.
  bool get hasChanges => switch (state.status) {
    CardioFormStatus.saved ||
    CardioFormStatus.closed ||
    CardioFormStatus.deleted => false,
    _ =>
      state.copyWith(issues: const {}, status: CardioFormStatus.editing) !=
          _start,
  };

  /// The session as it stands, for its pace or speed under the form.
  CardioSession get session => _check(state).$1;

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
      distance: _shownDistance(session.distanceKm, unit),
      calories: session.calories,
      heartRate: session.avgHeartRate,
      incline: session.incline,
      note: session.note ?? '',
    );
  }

  void setType(CardioType type) => _change(state.copyWith(type: type));
  void setDate(DateTime date) => _change(state.copyWith(date: date));
  void setDuration(Duration duration) =>
      _change(state.copyWith(duration: duration));

  /// In the unit the user sees; null clears it, as for the values below.
  void setDistance(double? value) =>
      _change(state.copyWith(distance: () => value));
  void setCalories(int? value) =>
      _change(state.copyWith(calories: () => value));
  void setHeartRate(int? value) =>
      _change(state.copyWith(heartRate: () => value));
  void setIncline(double? value) =>
      _change(state.copyWith(incline: () => value));
  void setNote(String text) => _change(state.copyWith(note: text));

  void _change(CardioFormState next) {
    if (state.status == CardioFormStatus.closed) return;
    final editing = next.copyWith(status: CardioFormStatus.editing);
    emit(_submitted ? editing.copyWith(issues: _check(editing).$2) : editing);
  }

  Future<void> save() async {
    if (!state.canSave || state.status == CardioFormStatus.closed) return;
    _submitted = true;
    final (session, issues) = _check(state);
    if (issues.isNotEmpty) {
      emit(state.copyWith(issues: issues, status: CardioFormStatus.editing));
      return;
    }
    final fields = _fields(session.type);
    await _run(
      CardioFormStatus.saving,
      CardioFormStatus.saved,
      CardioFormStatus.saveFailed,
      (uid) async {
        final result = await _saveSession((
          uid: uid,
          session: session,
          fields: fields,
        ));
        if (result.isOk && _initial == null) {
          unawaited(_analytics.cardioLog(session.type));
        }
        return result;
      },
    );
  }

  Future<void> delete() async {
    final id = _initial?.id;
    if (id == null || state.isBusy || state.status == CardioFormStatus.closed) {
      return;
    }
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
      emit(state.copyWith(status: CardioFormStatus.closed));
      return;
    }
    emit(state.copyWith(status: busy, issues: const {}));
    final failure = (await action(uid)).failureOrNull;
    if (isClosed || state.status == CardioFormStatus.closed) return;
    emit(
      failure == null
          ? state.copyWith(status: done)
          : state.copyWith(status: failed, failure: failure),
    );
  }

  bool _typeChanged(CardioType type) {
    final initial = _initial;
    return initial != null && type != initial.type;
  }

  /// The optional fields an edit writes: those the form shows, plus, after a
  /// type change, those the old type may have stored. A field the form does
  /// not show for an unchanged type, e.g. a newer app's type shown as
  /// "Other", is left as stored.
  Set<CardioField> _fields(CardioType type) {
    final changed = _typeChanged(type);
    return {
      CardioField.calories,
      CardioField.avgHeartRate,
      CardioField.note,
      if (type.distance || changed) CardioField.distanceKm,
      if (type.incline || changed) CardioField.incline,
    };
  }

  /// The session the values describe, and what is wrong with it. Fields
  /// the type does not use are left out.
  (CardioSession, Set<CardioIssue>) _check(CardioFormState input) {
    final type = input.type;
    final note = input.note.trim();
    final initial = _initial;
    final session = CardioSession(
      id: initial?.id,
      type: type,
      typeCode: initial != null && !_typeChanged(type)
          ? initial.typeCode
          : null,
      date: input.date,
      duration: input.duration,
      distanceKm: type.distance ? _distanceKm(input.distance) : null,
      calories: input.calories,
      avgHeartRate: input.heartRate,
      incline: type.incline ? input.incline : null,
      note: note.isEmpty ? null : note,
    );
    return (session, validateCardio(session, now: _clock()));
  }

  /// Keeps the stored km while the shown, rounded distance was not
  /// changed, so saving other changes does not drift it.
  double? _distanceKm(double? value) {
    if (value == null) return null;
    final initial = _initial?.distanceKm;
    if (initial != null && value == _shownDistance(initial, _unit)) {
      return initial;
    }
    return _unit.toKm(value);
  }

  /// [km] in [unit] to the 0.01 the distance picker steps by.
  static double? _shownDistance(double? km, DistanceUnit unit) =>
      km == null ? null : (unit.fromKm(km) * 100).round() / 100;

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
