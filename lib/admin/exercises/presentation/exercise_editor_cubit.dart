import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../access/domain/access_usecases.dart';
import '../../shell/editor_status.dart';
import '../domain/exercise_admin_usecases.dart';
import '../domain/exercise_draft.dart';

export '../../shell/editor_status.dart';

class ExerciseEditorState extends Equatable {
  const ExerciseEditorState({
    required this.isNew,
    this.draft = const ExerciseDraft(),
    this.loaded,
    this.library = const [],
    this.problems = const [],
    this.status = EditorStatus.editing,
    this.failure,
    this.accessRefreshed = false,
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

  /// After a save denied by the rules: the token was refreshed and still
  /// carries the admin claim, so saving again may work. (Without the claim,
  /// the access gate takes over.)
  final bool accessRefreshed;

  /// Changes whenever the draft is replaced from outside the form, so the
  /// form rebuilds its fields.
  final int formVersion;

  List<String> problemsFor(String field) => [
    for (final problem in problems)
      if (problem.field == field) problem.message,
  ];

  bool get isDirty => draft != (loaded?.draft ?? const ExerciseDraft());

  /// Whether saving with [status] (null: the current one) would write
  /// anything. A new exercise always can.
  bool canSave([ExerciseStatus? status]) {
    final stored = loaded;
    if (isNew || stored == null) return true;
    return draft.copyWith(status: status) != stored.draft;
  }

  ExerciseEditorState copyWith({
    bool? isNew,
    ExerciseDraft? draft,
    ExerciseRecord? loaded,
    List<ExerciseRecord>? library,
    List<ContentProblem>? problems,
    EditorStatus? status,
    Failure? failure,
    bool? accessRefreshed,
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
    accessRefreshed: status == null
        ? this.accessRefreshed
        : accessRefreshed ?? false,
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
    accessRefreshed,
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
    required this._checkAdminAccess,
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
  final CheckAdminAccess _checkAdminAccess;
  late final StreamSubscription<List<ExerciseRecord>> _library;
  String? _id;

  /// The last save went through but its new `updatedAt` is unknown; the next
  /// save reads it first.
  bool _updatedAtUnknown = false;

  /// Replaces the draft with the stored document, dropping local changes.
  Future<void> reload() async {
    final id = _id;
    if (id == null) return;
    emit(state.copyWith(status: EditorStatus.loading));
    final result = await _loadExerciseRecord(id);
    if (isClosed) return;
    emit(
      result.fold(
        (record) {
          _updatedAtUnknown = false;
          return state.copyWith(
            loaded: record,
            draft: record.draft,
            problems: const [],
            status: EditorStatus.editing,
            formVersion: state.formVersion + 1,
          );
        },
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

  /// Saves with the current status. Does nothing without changes.
  Future<void> save() => _save(state.draft);

  /// Saves and moves to [status]: draft, live (publish) or retired. Does
  /// nothing when neither the status nor anything else changes.
  Future<void> saveAs(ExerciseStatus status) =>
      _save(state.draft.copyWith(status: status));

  Future<void> _save(ExerciseDraft draft) async {
    if (state.status case EditorStatus.saving || EditorStatus.loading) return;
    if (!state.canSave(draft.status)) return;
    final problems = _validate(draft);
    if (problems.isNotEmpty) {
      return emit(
        state.copyWith(problems: problems, status: EditorStatus.editing),
      );
    }
    emit(state.copyWith(problems: const [], status: EditorStatus.saving));
    final Result<SaveOutcome> result;
    if (state.loaded == null) {
      result = await _createExercise(draft);
    } else {
      final base = await _confirmedBase();
      result = base == null
          ? const Ok(ChangedSinceLoaded())
          : await switch (base) {
              Ok(value: final loaded) => _updateExercise((
                draft: draft,
                loadedUpdatedAt: loaded.updatedAt,
              )),
              Err(:final failure) => Future.value(Err(failure)),
            };
    }
    if (isClosed) return;
    switch (result) {
      case Ok(value: Saved(:final record)):
        _id = draft.id;
        _updatedAtUnknown = record == null;
        emit(
          state.copyWith(
            isNew: false,
            loaded:
                record ?? ExerciseRecord(json: draft.toJson(), updatedAt: null),
            draft: draft,
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
      case Err(failure: final PermissionFailure failure):
        // The claim may have been revoked, or the token may just be stale:
        // a refreshed token tells. Without the claim, the access gate (which
        // follows token changes) leaves this page.
        final access = await _checkAdminAccess(true);
        if (isClosed) return;
        emit(
          state.copyWith(
            status: EditorStatus.saveFailed,
            failure: failure,
            accessRefreshed: access.valueOrNull ?? false,
          ),
        );
      case Err(:final failure):
        emit(state.copyWith(status: EditorStatus.saveFailed, failure: failure));
    }
  }

  /// The stored document to save over: the loaded one, or after a save whose
  /// `updatedAt` is unknown, the one stored now if it is still what that save
  /// wrote (null when someone changed it since).
  Future<Result<ExerciseRecord>?> _confirmedBase() async {
    final loaded = state.loaded!;
    if (!_updatedAtUnknown) return Ok(loaded);
    final result = await _loadExerciseRecord(loaded.id);
    if (result case Ok(value: final stored)) {
      if (stored.draft != loaded.draft) return null;
      _updatedAtUnknown = false;
    }
    return result;
  }

  List<ContentProblem> _validate(ExerciseDraft draft) =>
      validateExercise(draft, library: state.library, isNew: state.isNew);

  @override
  Future<void> close() async {
    await _library.cancel();
    return super.close();
  }
}
