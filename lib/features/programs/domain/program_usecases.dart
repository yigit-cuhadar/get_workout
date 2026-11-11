import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import 'active_program.dart';
import 'calendar_date.dart';
import 'catalogue_program.dart';
import 'catalogue_repository.dart';
import 'completed_days.dart';
import 'program.dart';
import 'program_editing.dart';
import 'program_repository.dart';
import 'program_schedule.dart';
import 'program_validation.dart';
import 'premium_status.dart';

/// [loggingTypes]: see [validateProgram].
typedef ProgramSave = ({
  String uid,
  Program program,
  Map<String, LoggingType> loggingTypes,
});
typedef ProgramRef = ({String uid, String id});

/// [nameOf] makes the copy's name from the original's.
typedef ProgramCopy = ({
  String uid,
  Program program,
  String Function(String name) nameOf,
});

/// [activeProgramId] is the program active when the delete was asked for.
typedef ProgramDelete = ({String uid, String id, String? activeProgramId});
typedef ProgramStart = ({String uid, Program program, List<int> weekdays});
typedef WeekdaysChange = ({
  String uid,
  ActiveProgram active,
  int dayCount,
  List<int> weekdays,
});

/// The three ways to resolve a missed day; see [ProgramSchedule.doToday],
/// [ProgramSchedule.moveToNextWeekday] and [ProgramSchedule.skip].
enum MissedDayChoice { doToday, moveToNextWeekday, skip }

/// [program] is the active program as it is now.
typedef MissedDayResolution = ({
  String uid,
  ActiveProgram active,
  Program program,
  MissedDayChoice choice,
});

/// [loggingTypes]: see [validateProgram].
typedef ExerciseAddition = ({
  String uid,
  Program program,
  int dayIndex,
  Exercise exercise,
  Map<String, LoggingType> loggingTypes,
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

/// Stores a copy of the program as the user's own (see [Program.duplicate])
/// and returns its id. It is copied as it is, unavailable exercises
/// included, so a copy never fails where the original loads.
class DuplicateProgram implements UseCase<String, ProgramCopy> {
  const DuplicateProgram(this._repository);
  final ProgramRepository _repository;

  @override
  Future<Result<String>> call(ProgramCopy params) => _repository.createProgram(
    params.uid,
    params.program.duplicate(params.nameOf),
  );
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

/// Resolves the active program's missed day as the user chose. Refused with
/// a [ValidationFailure] when no day is missed (any more), e.g. because
/// another device resolved it first.
class ResolveMissedDay implements UseCase<void, MissedDayResolution> {
  ResolveMissedDay(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final ProgramRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<void>> call(MissedDayResolution params) async {
    final program = params.program;
    final today = CalendarDate.of(_clock());
    if (program.days.isEmpty || program.id != params.active.programId) {
      return const Err(ValidationFailure('not the active program'));
    }
    final schedule = ProgramSchedule(
      params.active,
      dayCount: program.days.length,
      lengthWeeks: program.lengthWeeks,
    );
    if (!schedule.isMissed(today)) {
      return const Err(ValidationFailure('no missed day'));
    }
    return _repository.updateActiveProgram(params.uid, switch (params.choice) {
      MissedDayChoice.doToday => schedule.doToday(today),
      MissedDayChoice.moveToNextWeekday => schedule.moveToNextWeekday(today),
      MissedDayChoice.skip => schedule.skip(today),
    });
  }
}

/// Appends [ExerciseAddition.exercise] to a day of a stored program with
/// the default targets (see [defaultItem]) and saves it like
/// [SaveProgram]; refused with a [ValidationFailure] when the day is full or
/// the program would not be valid.
class AddExerciseToProgram implements UseCase<void, ExerciseAddition> {
  const AddExerciseToProgram(this._saveProgram);
  final SaveProgram _saveProgram;

  @override
  Future<Result<void>> call(ExerciseAddition params) async {
    final program = params.program;
    final day = program.days.elementAtOrNull(params.dayIndex);
    if (program.id == null ||
        day == null ||
        day.items.length >= ProgramLimits.maxItemsPerDay) {
      return const Err(ValidationFailure('no room on that day'));
    }
    final changed = program.copyWith(
      days: [
        for (final (i, d) in program.days.indexed)
          i == params.dayIndex
              ? d.copyWith(items: [...d.items, defaultItem(params.exercise)])
              : d,
      ],
    );
    return (await _saveProgram((
      uid: params.uid,
      program: changed,
      loggingTypes: params.loggingTypes,
    ))).map((_) {});
  }
}

class StopProgram implements UseCase<void, String> {
  const StopProgram(this._repository);
  final ProgramRepository _repository;

  /// [params] is the user's id.
  @override
  Future<Result<void>> call(String params) => _repository.stopProgram(params);
}

class WatchCatalogue {
  const WatchCatalogue(this._repository);
  final CatalogueRepository _repository;

  Stream<List<CatalogueProgram>> call() => _repository.watchPrograms();
}

class GetCatalogueDays implements UseCase<List<ProgramDay>, String> {
  const GetCatalogueDays(this._repository);
  final CatalogueRepository _repository;

  /// [params] is the catalogue program's id.
  @override
  Future<Result<List<ProgramDay>>> call(String params) =>
      _repository.getDays(params);
}

class WatchPremium {
  const WatchPremium(this._premium);
  final PremiumStatus _premium;

  Stream<bool?> call() => _premium.watch();
}
