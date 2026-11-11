import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import 'active_program.dart';
import 'calendar_date.dart';
import 'completed_days.dart';
import 'program.dart';
import 'program_repository.dart';
import 'program_schedule.dart';
import 'program_validation.dart';

/// [loggingTypes]: see [validateProgram].
typedef ProgramSave = ({
  String uid,
  Program program,
  Map<String, LoggingType> loggingTypes,
});
typedef ProgramRef = ({String uid, String id});

/// [activeProgramId] is the program active when the delete was asked for.
typedef ProgramDelete = ({String uid, String id, String? activeProgramId});
typedef ProgramStart = ({String uid, Program program, List<int> weekdays});
typedef WeekdaysChange = ({
  String uid,
  ActiveProgram active,
  int dayCount,
  List<int> weekdays,
});
typedef CompletedDaysQuery = ({
  String uid,
  String programId,
  CalendarDate from,
  CalendarDate to,
});

class WatchPrograms {
  const WatchPrograms(this._repository);
  final ProgramRepository _repository;

  Stream<List<Program>> call(String uid) => _repository.watchPrograms(uid);
}

class WatchActiveProgram {
  const WatchActiveProgram(this._repository);
  final ProgramRepository _repository;

  Stream<ActiveProgram?> call(String uid) =>
      _repository.watchActiveProgram(uid);
}

class WatchRejectedProgramWrites {
  const WatchRejectedProgramWrites(this._repository);
  final ProgramRepository _repository;

  Stream<Failure> call() => _repository.rejectedWrites;
}

class WatchCompletedDays {
  const WatchCompletedDays(this._completedDays);
  final CompletedDays _completedDays;

  Stream<List<CompletedDay>> call(CompletedDaysQuery query) => _completedDays
      .watch(query.uid, query.programId, from: query.from, to: query.to);
}

class GetProgram implements UseCase<Program, ProgramRef> {
  const GetProgram(this._repository);
  final ProgramRepository _repository;

  @override
  Future<Result<Program>> call(ProgramRef params) =>
      _repository.getProgram(params.uid, params.id);
}

/// Creates a program without an id, updates one with an id, and returns
/// its id. An invalid program is refused with a [ValidationFailure] and
/// never reaches the repository. The name is stored trimmed.
class SaveProgram implements UseCase<String, ProgramSave> {
  const SaveProgram(this._repository);
  final ProgramRepository _repository;

  @override
  Future<Result<String>> call(ProgramSave params) async {
    final validation = validateProgram(params.program, params.loggingTypes);
    if (!validation.isValid) return Err(ValidationFailure('$validation'));
    final program = params.program.copyWith(name: params.program.name.trim());
    final id = program.id;
    if (id == null) return _repository.createProgram(params.uid, program);
    return (await _repository.updateProgram(
      params.uid,
      program,
    )).map((_) => id);
  }
}

class DeleteProgram implements UseCase<void, ProgramDelete> {
  const DeleteProgram(this._repository);
  final ProgramRepository _repository;

  @override
  Future<Result<void>> call(ProgramDelete params) => _repository.deleteProgram(
    params.uid,
    params.id,
    clearActive: params.activeProgramId == params.id,
  );
}

/// Makes the program active from today, replacing any other, with one
/// weekday per program day.
class StartProgram implements UseCase<void, ProgramStart> {
  StartProgram(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final ProgramRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<void>> call(ProgramStart params) async {
    final id = params.program.id;
    if (id == null ||
        !ProgramSchedule.isValidWeekdays(
          params.weekdays,
          params.program.days.length,
        )) {
      return const Err(ValidationFailure('one weekday per program day'));
    }
    final now = _clock();
    return _repository.startProgram(
      params.uid,
      ProgramSchedule.start(
        programId: id,
        weekdays: params.weekdays,
        today: CalendarDate.of(now),
        startedAt: now,
      ),
    );
  }
}

/// Moves the active program to other weekdays; see
/// [ProgramSchedule.withWeekdays].
class ChangeWeekdays implements UseCase<void, WeekdaysChange> {
  ChangeWeekdays(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final ProgramRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<void>> call(WeekdaysChange params) async {
    if (!ProgramSchedule.isValidWeekdays(params.weekdays, params.dayCount)) {
      return const Err(ValidationFailure('one weekday per program day'));
    }
    final schedule = ProgramSchedule(params.active, dayCount: params.dayCount);
    return _repository.updateActiveProgram(
      params.uid,
      schedule.withWeekdays(params.weekdays, CalendarDate.of(_clock())),
    );
  }
}

class StopProgram implements UseCase<void, String> {
  const StopProgram(this._repository);
  final ProgramRepository _repository;

  /// [params] is the user's id.
  @override
  Future<Result<void>> call(String params) => _repository.stopProgram(params);
}
