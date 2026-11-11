import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../domain/exercise_admin_usecases.dart';
import '../domain/exercise_draft.dart';

enum EditorStatus {
  loading,
  loadFailed,
  editing,
  saving,

  /// The last save went through.
  saved,

  /// The document changed since it was loaded; saving is refused until the
  /// editor reloads it.
  changedSinceLoaded,
  saveFailed,
}

class ExerciseEditorState extends Equatable {
  const ExerciseEditorState({
    required this.isNew,
    this.draft = const ExerciseDraft(),
    this.loaded,
    this.library = const [],
    this.problems = const [],
    this.status = EditorStatus.editing,
    this.failure,
    this.formVersion = 0,
  });

  /// The id is set only while this is true.
  final bool isNew;
  final ExerciseDraft draft;

  /// The stored document the draft started from; null for a new exercise.
  final ExerciseRecord? loaded;

  /// Every loaded document, for the checks across exercises and pickers.
  final List<ExerciseRecord> library;

  /// Broken rules; filled by a save attempt and then kept current.
  final List<ContentProblem> problems;
  final EditorStatus status;

  /// Why loading or saving failed, with [EditorStatus.loadFailed] and
  /// [EditorStatus.saveFailed].
  final Failure? failure;

  /// Changes whenever the draft is replaced from outside the form, so the
  /// form rebuilds its fields.
  final int formVersion;

  List<String> problemsFor(String field) => [
    for (final problem in problems)
      if (problem.field == field) problem.message,
  ];

  bool get isDirty => draft != (loaded?.draft ?? const ExerciseDraft());

  ExerciseEditorState copyWith({
    bool? isNew,
    ExerciseDraft? draft,
    ExerciseRecord? loaded,
    List<ExerciseRecord>? library,
    List<ContentProblem>? problems,
    EditorStatus? status,
    Failure? failure,
    int? formVersion,
  }) => ExerciseEditorState(
    isNew: isNew ?? this.isNew,
    draft: draft ?? this.draft,
    loaded: loaded ?? this.loaded,
    library: library ?? this.library,
    problems: problems ?? this.problems,
    status: status ?? this.status,
    // A failure belongs to its status and goes with it.
    failure: status == null ? this.failure : failure,
    formVersion: formVersion ?? this.formVersion,
  );

  @override
  List<Object?> get props => [
    isNew,
    draft,
    loaded,
    library,
    problems,
    status,
    failure,
    formVersion,
  ];
}

/// Creates or edits one exercise. Every save is checked against the content
/// rules first, and refused by the repository when the document changed
/// since it was loaded.
class ExerciseEditorCubit extends Cubit<ExerciseEditorState> {
  /// Edits the exercise [id], or creates one when it is null.
  ExerciseEditorCubit({
    required String? id,
    required this._loadExerciseRecord,
    required WatchExerciseRecords watchExerciseRecords,
    required this._createExercise,
    required this._updateExercise,
  }) : _id = id,
       super(
         ExerciseEditorState(
           isNew: id == null,
           status: id == null ? EditorStatus.editing : EditorStatus.loading,
         ),
       ) {
    _library = watchExerciseRecords().listen(
      (library) => emit(state.copyWith(library: library)),
      // The list page shows stream failures; the checks run on what arrived.
      onError: (Object _) {},
    );
    if (id != null) unawaited(reload());
  }

  final LoadExerciseRecord _loadExerciseRecord;
  final CreateExercise _createExercise;
  final UpdateExercise _updateExercise;
  late final StreamSubscription<List<ExerciseRecord>> _library;
  String? _id;

  /// Replaces the draft with the stored document, dropping local changes.
  Future<void> reload() async {
    final id = _id;
    if (id == null) return;
    emit(state.copyWith(status: EditorStatus.loading));
    final result = await _loadExerciseRecord(id);
    if (isClosed) return;
    emit(
      result.fold(
        (record) => state.copyWith(
          loaded: record,
          draft: record.draft,
          problems: const [],
          status: EditorStatus.editing,
          formVersion: state.formVersion + 1,
        ),
        (failure) =>
            state.copyWith(status: EditorStatus.loadFailed, failure: failure),
      ),
    );
  }

  void change(ExerciseDraft Function(ExerciseDraft draft) edit) {
    var draft = edit(state.draft);
    if (!draft.takesIncrement && draft.incrementKg != null) {
      draft = draft.copyWith(incrementKg: null);
    }
    emit(
      state.copyWith(
        draft: draft,
        problems: state.problems.isEmpty ? null : _validate(draft),
        status: switch (state.status) {
          EditorStatus.changedSinceLoaded => EditorStatus.changedSinceLoaded,
          _ => EditorStatus.editing,
        },
      ),
    );
  }

  /// Saves with the current status.
  Future<void> save() => _save(state.draft);

  /// Saves and moves to [status]: draft, live (publish) or retired.
  Future<void> saveAs(ExerciseStatus status) =>
      _save(state.draft.copyWith(status: status));

  Future<void> _save(ExerciseDraft draft) async {
    if (state.status case EditorStatus.saving || EditorStatus.loading) return;
    final problems = _validate(draft);
    if (problems.isNotEmpty) {
      return emit(
        state.copyWith(problems: problems, status: EditorStatus.editing),
      );
    }
    emit(state.copyWith(problems: const [], status: EditorStatus.saving));
    final loaded = state.loaded;
    final result = loaded == null
        ? await _createExercise(draft)
        : await _updateExercise((
            draft: draft,
            loadedUpdatedAt: loaded.updatedAt,
          ));
    if (isClosed) return;
    switch (result) {
      case Ok(value: Saved(:final record)):
        _id = record.id;
        emit(
          state.copyWith(
            isNew: false,
            loaded: record,
            draft: record.draft,
            status: EditorStatus.saved,
          ),
        );
      case Ok(value: IdTaken()):
        emit(
          state.copyWith(
            problems: [
              ContentProblem('id', 'id "${draft.id}" is already used'),
            ],
            status: EditorStatus.editing,
          ),
        );
      case Ok(value: ChangedSinceLoaded()):
        emit(state.copyWith(status: EditorStatus.changedSinceLoaded));
      case Err(:final failure):
        emit(state.copyWith(status: EditorStatus.saveFailed, failure: failure));
    }
  }

  List<ContentProblem> _validate(ExerciseDraft draft) =>
      validateExercise(draft, library: state.library, isNew: state.isNew);

  @override
  Future<void> close() async {
    await _library.cancel();
    return super.close();
  }
}
