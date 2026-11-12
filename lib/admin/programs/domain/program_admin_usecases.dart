import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/exercise.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../../../features/programs/domain/program.dart';
import '../../../features/programs/domain/program_editing.dart';
import '../../exercises/domain/exercise_draft.dart';
import 'admin_program_repository.dart';
import 'program_draft.dart';

typedef ProgramUpdate = ({Map<String, Object?> content, ProgramVersion loaded});

class WatchProgramCards {
  const WatchProgramCards(this._repository);
  final AdminProgramRepository _repository;

  Stream<List<ProgramRecord>> call() => _repository.watchCards();
}

class LoadProgramRecord implements UseCase<ProgramRecord, String> {
  const LoadProgramRecord(this._repository);
  final AdminProgramRepository _repository;

  @override
  Future<Result<ProgramRecord>> call(String params) => _repository.load(params);
}

class CreateProgram
    implements UseCase<ProgramSaveOutcome, Map<String, Object?>> {
  const CreateProgram(this._repository);
  final AdminProgramRepository _repository;

  @override
  Future<Result<ProgramSaveOutcome>> call(Map<String, Object?> params) =>
      _repository.create(params);
}

class UpdateProgram implements UseCase<ProgramSaveOutcome, ProgramUpdate> {
  const UpdateProgram(this._repository);
  final AdminProgramRepository _repository;

  @override
  Future<Result<ProgramSaveOutcome>> call(ProgramUpdate params) =>
      _repository.update(params.content, loaded: params.loaded);
}

/// [records] by id, as the catalogue rules take the exercise library.
Map<String, ExerciseEntry> exerciseEntries(List<ExerciseRecord> records) => {
  for (final record in records) record.id: ExerciseEntry(record.json),
};

/// A new item for [exercise] with the app's default targets
/// ([defaultItem]), resting the exercise's default rest.
ProgramItem newProgramItem(ExerciseDraft exercise) =>
    defaultItem(
      Exercise.custom(
        id: exercise.id,
        name: exercise.name,
        loggingType: exercise.loggingType ?? LoggingType.reps,
        mainMuscles: exercise.mainMuscles,
      ),
    ).copyWith(
      restS: (exercise.defaultRestS ?? fallbackRestS).clamp(
        0,
        ProgramLimits.maxRestS,
      ),
    );

/// Every rule [draft] breaks: the rules of a single catalogue program
/// against [exercises], plus the ones across the catalogue that concern it,
/// checked against [catalogue] (the loaded cards): a new id is unused, and
/// its name and order are unique. The split of live programs into free and
/// premium is [CatalogueHealth]'s and never blocks a save. Problems across
/// the catalogue have the field `catalogue`.
List<ContentProblem> validateCatalogueProgram(
  ProgramDraft draft, {
  required Map<String, ExerciseEntry> exercises,
  required List<ProgramRecord> catalogue,
  required bool isNew,
}) {
  final content = draft.content(exercises);
  final problems = programProblems(content, exercises);
  if (isNew && catalogue.any((record) => record.id == draft.id)) {
    problems.add(ContentProblem('id', 'id "${draft.id}" is already used'));
  }
  // checkCatalogue reports a clash on the later of two programs, so with
  // the draft last its clashes are the errors naming it.
  final entry = ProgramEntry(content);
  final prefix = '${entry.where}: ';
  final check = checkCatalogue([
    for (final record in catalogue)
      if (record.id != draft.id) ProgramEntry(record.json),
    entry,
  ], exercises);
  problems.addAll([
    for (final error in check.errors)
      if (error.startsWith(prefix))
        ContentProblem('catalogue', error.substring(prefix.length)),
  ]);
  return problems;
}

/// What the catalogue rules would warn about [draft] once live: weekly sets
/// of a major muscle outside its level's band. Never blocks a save.
List<String> programWarnings(
  ProgramDraft draft,
  Map<String, ExerciseEntry> exercises,
) {
  final content = draft.content(exercises)
    ..['status'] = ExerciseStatus.live.code;
  final entry = ProgramEntry(content);
  final prefix = '${entry.where}: ';
  return [
    for (final warning in checkCatalogue([entry], exercises).warnings)
      warning.startsWith(prefix) ? warning.substring(prefix.length) : warning,
  ];
}

/// What the catalogue-wide rules say about the loaded cards: unique ids,
/// names and orders, and the split of live programs into free and premium.
/// Shown as a summary; never enforced on save, since fixing one usually
/// takes edits to several programs. The weekly-set warnings need every
/// program's days, so each program's editor shows its own.
class CatalogueHealth extends Equatable {
  const CatalogueHealth(this.errors);

  factory CatalogueHealth.of(List<ProgramRecord> cards) => CatalogueHealth(
    checkCatalogue([
      for (final card in cards) ProgramEntry(card.json),
    ], const {}).errors,
  );

  final List<String> errors;

  bool get isHealthy => errors.isEmpty;

  @override
  List<Object?> get props => [errors];
}
