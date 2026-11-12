import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/active_program.dart';
import '../domain/calendar_date.dart';
import '../domain/completed_days.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import '../domain/program_usecases.dart';

enum ProgramListStatus { loading, ready, failure }

class ProgramListState extends Equatable {
  const ProgramListState({
    this.status = ProgramListStatus.loading,
    this.programs = const [],
    this.active,
    this.weekPlan = const [],
    this.finished = false,
    this.nextDate,
    this.missed,
    this.moveDate,
    this.failure,
    this.writeRejected = false,
    this.resolving = false,
    this.resolveFailure,
    this.premium,
  });

  final ProgramListStatus status;

  /// By name.
  final List<Program> programs;

  /// As stored; it may name a program that no longer exists.
  final ActiveProgram? active;

  /// This week's plan of the active program.
  final List<PlannedDay> weekPlan;

  /// The active program has run its length.
  final bool finished;

  /// The date [nextDayIndex] is planned for as of today: the first of the
  /// program's upcoming days, so a missed day falls on today or the next
  /// selected weekday. Null without an active program or once it finished.
  final CalendarDate? nextDate;

  /// The active program's next day, when its date has passed undone.
  final PlannedDay? missed;

  /// Where [MissedDayChoice.moveToNextWeekday] would move [missed].
  final CalendarDate? moveDate;
  final Failure? failure;

  /// The server refused a write that already looked done; tell the user,
  /// then call [ProgramListCubit.rejectionShown].
  final bool writeRejected;

  /// A missed-day choice is being saved.
  final bool resolving;

  /// Saving a missed-day choice failed; tell the user, then call
  /// [ProgramListCubit.resolveFailureShown].
  final Failure? resolveFailure;

  /// Whether the user has premium; null while unknown.
  final bool? premium;

  Program? program(String id) =>
      programs.where((program) => program.id == id).firstOrNull;

  /// The active program, when it still exists.
  Program? get activeProgram {
    final id = active?.programId;
    return id == null ? null : program(id);
  }

  ProgramAccess access(Program program) => programAccess(program, premium);

  /// The active program's day to do next, unless it has run its length.
  int? get nextDayIndex {
    final days = activeProgram?.days.length ?? 0;
    if (days == 0 || finished) return null;
    return active!.nextDayIndex % days;
  }

  List<Program> get otherPrograms => [
    for (final program in programs)
      if (program.id != active?.programId) program,
  ];

  ProgramListState copyWith({
    bool? writeRejected,
    bool? resolving,
    Failure? Function()? resolveFailure,
    bool? Function()? premium,
  }) => ProgramListState(
    status: status,
    programs: programs,
    active: active,
    weekPlan: weekPlan,
    finished: finished,
    nextDate: nextDate,
    missed: missed,
    moveDate: moveDate,
    failure: failure,
    writeRejected: writeRejected ?? this.writeRejected,
    resolving: resolving ?? this.resolving,
    resolveFailure: resolveFailure != null
        ? resolveFailure()
        : this.resolveFailure,
    premium: premium != null ? premium() : this.premium,
  );

  @override
  List<Object?> get props => [
    status,
    programs,
    active,
    weekPlan,
    finished,
    nextDate,
    missed,
    moveDate,
    failure,
    writeRejected,
    resolving,
    resolveFailure,
    premium,
  ];
}

/// The programs and the active program of whoever is signed in, with this
/// week's plan. Resets to loading on every user change, so a previous
/// user's programs are never shown.
class ProgramListCubit extends Cubit<ProgramListState> {
  ProgramListCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchPrograms,
    required this._watchActiveProgram,
    required this._watchCompletedDays,
    required WatchRejectedProgramWrites watchRejectedWrites,
    required this._resolveMissedDay,
    required WatchPremium watchPremium,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const ProgramListState()) {
    _premiumSubscription = watchPremium().listen(
      (premium) => emit(state.copyWith(premium: () => premium)),
      onError: (Object error, StackTrace stack) =>
          Log.e('programs', 'premium status failed', error, stack),
    );
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
    _rejectedSubscription = watchRejectedWrites().listen(
      (_) => emit(state.copyWith(writeRejected: true)),
    );
  }

  final WatchPrograms _watchPrograms;
  final WatchActiveProgram _watchActiveProgram;
  final WatchCompletedDays _watchCompletedDays;
  final ResolveMissedDay _resolveMissedDay;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
  late final StreamSubscription<bool?> _premiumSubscription;
  StreamSubscription<List<Program>>? _programsSubscription;
  StreamSubscription<ActiveProgram?>? _activeSubscription;
  StreamSubscription<List<CompletedDay>>? _completedSubscription;
  String? _uid;

  /// Null until the first value arrives for the current user.
  List<Program>? _programs;
  ActiveProgram? _active;
  bool _activeKnown = false;
  List<CompletedDay> _completed = const [];

  /// The program and week the completed days are followed for.
  (String, CalendarDate)? _completedFor;

  CalendarDate get _today => CalendarDate.of(_clock());

  void _onUser(String? uid) {
    _uid = uid;
    // Nothing of the previous user's, transient notices included.
    _follow(keepNotices: false);
  }

  /// Subscribes again after a failure.
  void retry() => _follow();

  void rejectionShown() {
    if (state.writeRejected) emit(state.copyWith(writeRejected: false));
  }

  void resolveFailureShown() =>
      emit(state.copyWith(resolveFailure: () => null));

  /// Resolves the missed day of the active program as the user chose.
  Future<void> resolveMissed(MissedDayChoice choice) async {
    final uid = _uid;
    final active = state.active;
    final program = state.activeProgram;
    if (uid == null ||
        active == null ||
        program == null ||
        state.missed == null ||
        state.resolving ||
        state.access(program) != ProgramAccess.open) {
      return;
    }
    emit(state.copyWith(resolving: true));
    final failure = (await _resolveMissedDay((
      uid: uid,
      active: active,
      program: program,
      choice: choice,
    ))).failureOrNull;
    // A result for a previous user says nothing about the current one.
    if (isClosed || _uid != uid) return;
    emit(state.copyWith(resolving: false, resolveFailure: () => failure));
  }

  /// Moves the plan to the current day and week, e.g. after the app slept
  /// over midnight.
  void refreshNow() {
    if (state.status != ProgramListStatus.ready) return;
    _followCompleted();
    _emitReady();
  }

  void _follow({bool keepNotices = true}) {
    _cancel();
    _programs = null;
    _active = null;
    _activeKnown = false;
    final loading = ProgramListState(
      writeRejected: keepNotices && state.writeRejected,
      premium: state.premium,
    );
    if (state != loading) emit(loading);
    final uid = _uid;
    if (uid == null) return;
    _programsSubscription = _watchPrograms(uid).listen((programs) {
      _programs = programs;
      _emitReady();
    }, onError: _fail);
    _activeSubscription = _watchActiveProgram(uid).listen((active) {
      _active = active;
      _activeKnown = true;
      _followCompleted();
      _emitReady();
    }, onError: _fail);
  }

  void _followCompleted() {
    final uid = _uid;
    final active = _active;
    final week = _today.weekStart;
    final key = active == null ? null : (active.programId, week);
    if (key == _completedFor) return;
    _completedFor = key;
    unawaited(_completedSubscription?.cancel());
    _completedSubscription = null;
    _completed = const [];
    if (uid == null || active == null) return;
    _completedSubscription =
        _watchCompletedDays((
          uid: uid,
          programId: active.programId,
          from: week,
          to: week.addDays(6),
        )).listen(
          (days) {
            _completed = days;
            _emitReady();
          },
          // Without done days the plan still shows; nothing else depends on
          // them.
          onError: (Object error, StackTrace stack) =>
              Log.e('programs', 'completed days failed', error, stack),
        );
  }

  void _emitReady() {
    final programs = _programs;
    if (programs == null || !_activeKnown) return;
    final active = _active;
    final program = active == null
        ? null
        : programs.where((p) => p.id == active.programId).firstOrNull;
    final today = _today;
    final schedule = program == null || program.days.isEmpty
        ? null
        : ProgramSchedule(
            active!,
            dayCount: program.days.length,
            lengthWeeks: program.lengthWeeks,
          );
    final finished = schedule?.isFinished(today) ?? false;
    // Done on its date without the program moving on is not missed; only
    // this week's done days are known.
    final missed =
        schedule != null &&
        schedule.isMissed(today) &&
        !_completed.contains(
          CompletedDay(date: active!.nextDate, dayIndex: schedule.nextDayIndex),
        );
    emit(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: programs,
        active: active,
        weekPlan: schedule?.weekPlan(today, completed: _completed) ?? const [],
        finished: finished,
        nextDate: finished ? null : schedule?.upcoming(today).firstOrNull?.date,
        missed: missed
            ? PlannedDay(
                date: active.nextDate,
                dayIndex: schedule.nextDayIndex,
                status: PlannedStatus.missed,
              )
            : null,
        moveDate: missed ? schedule.moveToNextWeekday(today).nextDate : null,
        writeRejected: state.writeRejected,
        resolving: state.resolving,
        resolveFailure: state.resolveFailure,
        premium: state.premium,
      ),
    );
  }

  void _fail(Object error) {
    _cancel();
    emit(
      ProgramListState(
        status: ProgramListStatus.failure,
        failure: error is Failure ? error : UnknownFailure('$error', error),
        writeRejected: state.writeRejected,
        premium: state.premium,
      ),
    );
  }

  void _cancel() {
    unawaited(_programsSubscription?.cancel());
    unawaited(_activeSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    _programsSubscription = null;
    _activeSubscription = null;
    _completedSubscription = null;
    _completedFor = null;
    _completed = const [];
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _rejectedSubscription.cancel();
    await _premiumSubscription.cancel();
    _cancel();
    return super.close();
  }
}
