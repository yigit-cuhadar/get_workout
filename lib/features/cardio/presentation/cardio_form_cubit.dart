import 'dart:async';

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

  /// The signed-in user changed; the form must close.
  closed,
}

/// The form's inputs, as typed; distance in the unit the user sees.
class CardioFormState extends Equatable {
  const CardioFormState({
    required this.type,
    required this.date,
    this.hours = '',
    this.minutes = '',
    this.seconds = '',
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
  final String hours;
  final String minutes;
  final String seconds;
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
    String? hours,
    String? minutes,
    String? seconds,
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
    hours: hours ?? this.hours,
    minutes: minutes ?? this.minutes,
    seconds: seconds ?? this.seconds,
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
    hours,
    minutes,
    seconds,
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
/// [unit] and converted to km only here. Closes when the signed-in user
/// changes, so it never shows or writes another user's session.
class CardioFormCubit extends Cubit<CardioFormState> {
  CardioFormCubit({
    required this._saveSession,
    required this._deleteSession,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required this._unit,
    this._initial,
    DateTime Function()? clock,
  }) : _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(_initialState(_initial, _unit, clock ?? DateTime.now)) {
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
  final DeleteCardioSession _deleteSession;
  final GetCurrentUser _getCurrentUser;
  final DistanceUnit _unit;
  final CardioSession? _initial;
  final DateTime Function() _clock;

  /// The user the form was opened for.
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;
  bool _submitted = false;

  /// Each part of the duration; more is more than a day anyway, and larger
  /// numbers could overflow [Duration].
  static const _maxDurationPart = Duration.secondsPerDay;

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
    final duration = session.duration;
    final incline = session.incline;
    return CardioFormState(
      type: session.type,
      date: session.date,
      hours: '${duration.inHours}',
      minutes: '${duration.inMinutes % 60}',
      seconds: '${duration.inSeconds % 60}',
      distance: _distanceText(session.distanceKm, unit),
      calories: session.calories?.toString() ?? '',
      heartRate: session.avgHeartRate?.toString() ?? '',
      incline: incline == null ? '' : formatDecimal(incline, 1),
      note: session.note ?? '',
    );
  }

  void setType(CardioType type) => _change(state.copyWith(type: type));
  void setDate(DateTime date) => _change(state.copyWith(date: date));
  void setDuration({String? hours, String? minutes, String? seconds}) =>
      _change(state.copyWith(hours: hours, minutes: minutes, seconds: seconds));
  void setDistance(String text) => _change(state.copyWith(distance: text));
  void setCalories(String text) => _change(state.copyWith(calories: text));
  void setHeartRate(String text) => _change(state.copyWith(heartRate: text));
  void setIncline(String text) => _change(state.copyWith(incline: text));
  void setNote(String text) => _change(state.copyWith(note: text));

  void _change(CardioFormState next) {
    if (state.status == CardioFormStatus.closed) return;
    final editing = next.copyWith(status: CardioFormStatus.editing);
    emit(_submitted ? editing.copyWith(issues: _check(editing).$2) : editing);
  }

  Future<void> save() async {
    if (state.isBusy || state.status == CardioFormStatus.closed) return;
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
      (uid) => _saveSession((uid: uid, session: session, fields: fields)),
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
      if (value == null || !value.isFinite) {
        unreadable.add(issue);
        return null;
      }
      return value;
    }

    int? part(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return 0;
      final value = int.tryParse(trimmed);
      return value == null || value < 0 || value > _maxDurationPart
          ? null
          : value;
    }

    final hours = part(input.hours);
    final minutes = part(input.minutes);
    final seconds = part(input.seconds);
    final durationReadable =
        hours != null && minutes != null && seconds != null;
    final distance = read(
      type.distance,
      input.distance,
      double.tryParse,
      CardioIssue.distanceOutOfRange,
    );
    final note = input.note.trim();
    final initial = _initial;
    final session = CardioSession(
      id: initial?.id,
      type: type,
      typeCode: initial != null && !_typeChanged(type)
          ? initial.typeCode
          : null,
      date: input.date,
      duration: durationReadable
          ? Duration(hours: hours, minutes: minutes, seconds: seconds)
          : Duration.zero,
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
    final issues = {...unreadable, ...validateCardio(session, now: _clock())};
    if (!durationReadable) {
      issues
        ..remove(CardioIssue.durationMissing)
        ..add(CardioIssue.durationTooLong);
    }
    return (session, issues);
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

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
