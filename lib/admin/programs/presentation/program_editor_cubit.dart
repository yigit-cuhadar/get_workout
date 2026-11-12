import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/grouping.dart' as grouping;
import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../../../features/programs/domain/program.dart';
import '../../access/domain/access_usecases.dart';
import '../../exercises/domain/exercise_admin_usecases.dart';
import '../../exercises/domain/exercise_draft.dart';
import '../../shell/editor_status.dart';
import '../domain/program_admin_usecases.dart';
import '../domain/program_draft.dart';

class ProgramEditorState extends Equatable {
  const ProgramEditorState({
    required this.isNew,
    this.draft = const ProgramDraft(),
    this.loaded,
    this.catalogue,
    this.exercises = const {},
    this.entries = const {},
    this.problems = const [],
    this.status = EditorStatus.editing,
    this.failure,
    this.accessRefreshed = false,
    this.formVersion = 0,
  });

  /// The id is set only while this is true.
  final bool isNew;
  final ProgramDraft draft;

  /// The stored program the draft started from; null for a new one.
  final ProgramRecord? loaded;

  /// Every loaded card, for the checks across programs.
  /// Null until it first arrives; the checks across programs need it, so
  /// nothing is saved before.
  final List<ProgramRecord>? catalogue;

  /// Every loaded exercise by id, for the picker and the rules.
  final Map<String, ExerciseRecord> exercises;

  /// [exercises] as the catalogue rules take them.
  final Map<String, ExerciseEntry> entries;

  /// Broken rules; filled by a save attempt and then kept current.
  final List<ContentProblem> problems;
  final EditorStatus status;

  /// Why loading or saving failed, with [EditorStatus.loadFailed] and
  /// [EditorStatus.saveFailed].
  final Failure? failure;

  /// After a save denied by the rules: the token was refreshed and still
  /// carries the admin claim, so saving again may work.
  final bool accessRefreshed;

  /// Changes whenever the draft changes other than through a field (a
  /// reload, a day or an exercise added, moved or removed), so the form
  /// rebuilds its fields.
  final int formVersion;

  List<String> problemsFor(String field) => [
    for (final problem in problems)
      if (problem.field == field) problem.message,
  ];

  /// Problems of [field] and of anything inside it, e.g. `days[0]` has
  /// those of `days[0].items[1].sets`.
  List<String> problemsWithin(String field) => [
    for (final problem in problems)
      if (problem.field == field ||
          problem.field.startsWith('$field.') ||
          problem.field.startsWith('$field['))
        problem.message,
  ];

  bool get isDirty => draft != (loaded?.draft ?? const ProgramDraft());

  /// The draft as it would be stored, with its computed fields.
  Map<String, Object?> get content => draft.content(entries);

  /// Minutes per day and weekly sets per muscle of the draft.
  ProgramSummary get summary =>
      summarizeProgram(ProgramEntry(content), entries);

  /// What the catalogue rules would warn about the draft once live.
  List<String> get warnings => programWarnings(draft, entries);

  /// Whether saving with [status] (null: the current one) would write
  /// anything. A new program always can.
  bool canSave([ExerciseStatus? status]) {
    final stored = loaded;
    if (isNew || stored == null) return true;
    return draft.copyWith(status: status) != stored.draft;
  }

  ProgramEditorState copyWith({
    bool? isNew,
    ProgramDraft? draft,
    ProgramRecord? loaded,
    List<ProgramRecord>? catalogue,
    Map<String, ExerciseRecord>? exercises,
    Map<String, ExerciseEntry>? entries,
    List<ContentProblem>? problems,
    EditorStatus? status,
    Failure? failure,
    bool? accessRefreshed,
    int? formVersion,
  }) => ProgramEditorState(
    isNew: isNew ?? this.isNew,
    draft: draft ?? this.draft,
    loaded: loaded ?? this.loaded,
    catalogue: catalogue ?? this.catalogue,
    exercises: exercises ?? this.exercises,
    entries: entries ?? this.entries,
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
    catalogue,
    exercises,
    entries,
    problems,
    status,
    failure,
    accessRefreshed,
    formVersion,
  ];
}

/// Creates or edits one ready-made program. Every save is checked against
/// the catalogue rules first, and refused by the repository when the
/// program changed since it was loaded.
class ProgramEditorCubit extends Cubit<ProgramEditorState> {
  /// Edits the program [id], or creates one when it is null.
  ProgramEditorCubit({
    required String? id,
    required this._loadProgramRecord,
    required WatchProgramCards watchProgramCards,
    required WatchExerciseRecords watchExerciseRecords,
    required this._createProgram,
    required this._updateProgram,
    required this._checkAdminAccess,
  }) : _id = id,
       super(
         ProgramEditorState(
           isNew: id == null,
           status: id == null ? EditorStatus.editing : EditorStatus.loading,
         ),
       ) {
    // The list pages show stream failures; the checks run on what arrived.
    _catalogue = watchProgramCards().listen((catalogue) {
      emit(state.copyWith(catalogue: catalogue));
      if (state.problems.isNotEmpty) {
        emit(state.copyWith(problems: _validate(state.draft)));
      }
    }, onError: (Object _) {});
    _exercises = watchExerciseRecords().listen(
      (records) => emit(
        state.copyWith(
          exercises: {for (final record in records) record.id: record},
          entries: exerciseEntries(records),
        ),
      ),
      onError: (Object _) {},
    );
    if (id != null) unawaited(reload());
  }

  final LoadProgramRecord _loadProgramRecord;
  final CreateProgram _createProgram;
  final UpdateProgram _updateProgram;
  final CheckAdminAccess _checkAdminAccess;
  late final StreamSubscription<List<ProgramRecord>> _catalogue;
  late final StreamSubscription<List<ExerciseRecord>> _exercises;
  String? _id;

  /// The last save went through but its new version is unknown; the next
  /// save reads it first.
  bool _versionUnknown = false;

  /// Replaces the draft with the stored program, dropping local changes.
  Future<void> reload() async {
    final id = _id;
    if (id == null) return;
    emit(state.copyWith(status: EditorStatus.loading));
    final result = await _loadProgramRecord(id);
    if (isClosed) return;
    emit(
      result.fold(
        (record) {
          _versionUnknown = false;
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

  /// Applies a change typed into a field.
  void change(ProgramDraft Function(ProgramDraft draft) edit) =>
      _apply(edit(state.draft), rebuildForm: false);

  void addDay() => _editDays((days) => [...days, const ProgramDay()]);

  void removeDay(int day) => _editDays((days) => [...days]..removeAt(day));

  void moveDay(int from, int to) => _editDays((days) {
    final moved = [...days];
    moved.insert(to, moved.removeAt(from));
    return moved;
  });

  void renameDay(int day, String name) => change(
    (draft) => draft.copyWith(
      days: [...draft.days]..[day] = draft.days[day].copyWith(name: name),
    ),
  );

  /// Appends [exerciseId] to [day] with the app's default targets.
  void addExercise(int day, String exerciseId) {
    final exercise = state.exercises[exerciseId];
    if (exercise == null) return;
    _editItems(day, (items) => [...items, newProgramItem(exercise.draft)]);
  }

  /// Applies a change typed into a field of an item.
  void changeItem(
    int day,
    int item,
    ProgramItem Function(ProgramItem item) edit,
  ) => change(
    (draft) => draft.copyWith(
      days: [...draft.days]
        ..[day] = draft.days[day].copyWith(
          items: [...draft.days[day].items]
            ..[item] = edit(draft.days[day].items[item]),
        ),
    ),
  );

  void removeItem(int day, int item) =>
      _editItems(day, (items) => grouping.removeItem(items, item));

  void moveItem(int day, int from, int to) =>
      _editItems(day, (items) => grouping.moveItem(items, from, to));

  void linkWithNext(int day, int item) =>
      _editItems(day, (items) => grouping.linkWithNext(items, item));

  void ungroup(int day, int item) =>
      _editItems(day, (items) => grouping.ungroup(items, item));

  void _editDays(List<ProgramDay> Function(List<ProgramDay> days) edit) =>
      _apply(
        state.draft.copyWith(days: edit(state.draft.days)),
        rebuildForm: true,
      );

  void _editItems(
    int day,
    List<ProgramItem> Function(List<ProgramItem> items) edit,
  ) => _editDays(
    (days) =>
        [...days]..[day] = days[day].copyWith(items: edit(days[day].items)),
  );

  void _apply(ProgramDraft draft, {required bool rebuildForm}) {
    emit(
      state.copyWith(
        draft: draft,
        problems: state.problems.isEmpty ? null : _validate(draft),
        status: switch (state.status) {
          EditorStatus.changedSinceLoaded => EditorStatus.changedSinceLoaded,
          _ => EditorStatus.editing,
        },
        formVersion: rebuildForm ? state.formVersion + 1 : null,
      ),
    );
  }

  /// Saves with the current status. Does nothing without changes.
  Future<void> save() => _save(state.draft);

  /// Saves and moves to [status]: draft, live (publish) or retired. Does
  /// nothing when neither the status nor anything else changes.
  Future<void> saveAs(ExerciseStatus status) =>
      _save(state.draft.copyWith(status: status));

  Future<void> _save(ProgramDraft draft) async {
    if (state.status case EditorStatus.saving || EditorStatus.loading) return;
    if (!state.canSave(draft.status)) return;
    final problems = _validate(draft);
    if (problems.isNotEmpty) {
      return emit(
        state.copyWith(problems: problems, status: EditorStatus.editing),
      );
    }
    emit(state.copyWith(problems: const [], status: EditorStatus.saving));
    final content = draft.content(state.entries);
    final Result<ProgramSaveOutcome> result;
    if (state.loaded == null) {
      result = await _createProgram(content);
    } else {
      final base = await _confirmedBase();
      result = base == null
          ? const Ok(ProgramChangedSinceLoaded())
          : await switch (base) {
              Ok(value: final loaded) => _updateProgram((
                content: content,
                loaded: loaded.version,
              )),
              Err(:final failure) => Future.value(Err(failure)),
            };
    }
    if (isClosed) return;
    switch (result) {
      case Ok(value: ProgramSaved(:final record)):
        _id = draft.id;
        // Read back as someone else saved it right after this save: what
        // this save wrote is the base, so the next save checks it first
        // and is refused.
        final overtaken = record != null && record.draft != draft;
        _versionUnknown = record == null || overtaken;
        emit(
          state.copyWith(
            isNew: false,
            loaded: record == null || overtaken
                ? ProgramRecord(
                    json: content,
                    version: (card: null, detail: null),
                  )
                : record,
            draft: draft,
            status: overtaken
                ? EditorStatus.changedSinceLoaded
                : EditorStatus.saved,
          ),
        );
      case Ok(value: ProgramIdTaken()):
        emit(
          state.copyWith(
            problems: [
              ContentProblem('id', 'id "${draft.id}" is already used'),
            ],
            status: EditorStatus.editing,
          ),
        );
      case Ok(value: ProgramChangedSinceLoaded()):
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

  /// The stored program to save over: the loaded one, or after a save whose
  /// version is unknown, the one stored now if it is still what that save
  /// wrote (null when someone changed it since).
  Future<Result<ProgramRecord>?> _confirmedBase() async {
    final loaded = state.loaded!;
    if (!_versionUnknown) return Ok(loaded);
    final result = await _loadProgramRecord(loaded.id);
    if (result case Ok(value: final stored)) {
      if (stored.draft != loaded.draft) return null;
      _versionUnknown = false;
    }
    return result;
  }

  List<ContentProblem> _validate(ProgramDraft draft) {
    final catalogue = state.catalogue;
    if (catalogue == null) return const [catalogueNotLoaded];
    return validateCatalogueProgram(
      draft,
      exercises: state.entries,
      catalogue: catalogue,
      isNew: state.isNew,
    );
  }

  /// Refuses a save until the other programs are loaded: without them a
  /// clashing id, name or order would go unnoticed.
  static const catalogueNotLoaded = ContentProblem(
    'catalogue',
    'The other programs have not loaded yet, so the id, name and order '
        'cannot be checked. Wait for the program list, or reload the page.',
  );

  @override
  Future<void> close() async {
    await _catalogue.cancel();
    await _exercises.cancel();
    return super.close();
  }
}
