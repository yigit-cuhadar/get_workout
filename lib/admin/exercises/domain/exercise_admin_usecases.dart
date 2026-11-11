import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import 'admin_exercise_repository.dart';
import 'exercise_draft.dart';

typedef ExerciseUpdate = ({ExerciseDraft draft, DateTime? loadedUpdatedAt});

class WatchExerciseRecords {
  const WatchExerciseRecords(this._repository);
  final AdminExerciseRepository _repository;

  Stream<List<ExerciseRecord>> call() => _repository.watchAll();
}

class LoadExerciseRecord implements UseCase<ExerciseRecord, String> {
  const LoadExerciseRecord(this._repository);
  final AdminExerciseRepository _repository;

  @override
  Future<Result<ExerciseRecord>> call(String params) =>
      _repository.load(params);
}

class CreateExercise implements UseCase<SaveOutcome, ExerciseDraft> {
  const CreateExercise(this._repository);
  final AdminExerciseRepository _repository;

  @override
  Future<Result<SaveOutcome>> call(ExerciseDraft params) =>
      _repository.create(params);
}

class UpdateExercise implements UseCase<SaveOutcome, ExerciseUpdate> {
  const UpdateExercise(this._repository);
  final AdminExerciseRepository _repository;

  @override
  Future<Result<SaveOutcome>> call(ExerciseUpdate params) =>
      _repository.update(params.draft, loadedUpdatedAt: params.loadedUpdatedAt);
}

/// Every rule [draft] breaks: the content rules of a single exercise, plus
/// the ones across the library that can be checked against [library] (the
/// loaded documents): a new id is unused, [nameProblems] and
/// [referenceProblems]. Rules about the live library as a whole are
/// [LibraryHealth]'s and never block a save.
List<ContentProblem> validateExercise(
  ExerciseDraft draft, {
  required List<ExerciseRecord> library,
  required bool isNew,
}) {
  final entry = ExerciseEntry(draft.toJson());
  final problems = exerciseProblems(entry.data);
  final ids = {for (final record in library) record.id};
  if (isNew && ids.contains(draft.id)) {
    problems.add(ContentProblem('id', 'id "${draft.id}" is already used'));
  }
  problems
    ..addAll(
      nameProblems(entry, [
        for (final record in library)
          if (record.id != draft.id) ExerciseEntry(record.json),
      ]),
    )
    ..addAll(referenceProblems(entry, ids));
  return problems;
}

/// What the library-wide content rules say about the loaded documents. Shown
/// as a summary; never enforced on save, since fixing one usually takes
/// edits to several exercises.
class LibraryHealth extends Equatable {
  const LibraryHealth({
    required this.errors,
    required this.warnings,
    required this.invalidIds,
  });

  factory LibraryHealth.of(List<ExerciseRecord> records) {
    final check = checkLibrary([
      for (final record in records) ExerciseEntry(record.json),
    ]);
    return LibraryHealth(
      errors: check.errors,
      warnings: check.warnings,
      invalidIds: [
        for (final record in records)
          if (exerciseProblems(record.json).isNotEmpty) record.id,
      ],
    );
  }

  /// Broken library-wide rules: popularity and family ranks of live
  /// exercises, coverage minimums, names, references.
  final List<String> errors;
  final List<String> warnings;

  /// Documents that break the rules of a single exercise, e.g. edited in the
  /// console; the import would reject them too.
  final List<String> invalidIds;

  bool get isHealthy => errors.isEmpty && invalidIds.isEmpty;

  @override
  List<Object?> get props => [errors, warnings, invalidIds];
}
