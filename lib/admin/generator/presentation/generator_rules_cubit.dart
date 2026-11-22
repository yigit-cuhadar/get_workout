import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../access/domain/access_usecases.dart';
import '../domain/generator_rules.dart';
import '../domain/generator_rules_usecases.dart';
import '../domain/rules_changes.dart';
import 'rules_text.dart';

/// Where the draft stands for the simulator.
enum DraftCheck {
  /// No changes against the loaded rules.
  unchanged,

  /// Changed, and its check is still to come or under way.
  checking,

  /// Changed, and its check failed.
  unchecked,

  /// Checked, with problems.
  problems,

  /// Checked without problems: it may be run.
  ready,
}

enum PublishStatus {
  idle,

  /// Publishing, and loading the version it made.
  publishing,

  /// The last publish went through ([GeneratorRulesState.published]).
  published,
  failed,
}

class GeneratorRulesState extends Equatable {
  GeneratorRulesState({
    this.loaded,
    this.loadFailure,
    this.loading = false,
    this.draft,
    this.newTemplates = const {},
    this.restoring,
    this.check,
    this.checked,
    this.checking = false,
    this.checkFailure,
    this.publishedFindings = const {},
    this.publishedChecking = false,
    this.publishedCheckFailure,
    this.publishStatus = PublishStatus.idle,
    this.publishFailure,
    this.accessRefreshed = false,
    this.published,
    this.stale = false,
    this.historyOpen = false,
    this.history,
    this.historyFailure,
    this.restoreLoading,
    this.restoreFailure,
    this.tab = RulesTab.templates,
    this.template = 0,
    this.day = 0,
    this.dosingGoal = 'build_muscle',
  });

  /// The current version; null until first loaded.
  final StoredRules? loaded;
  final Failure? loadFailure;
  final bool loading;

  /// The rules every tab edits; null while none are loaded.
  final GeneratorRules? draft;

  /// The indices of the draft's templates added in it: new whatever their
  /// id, so typing an id never turns one into an edit of another.
  final Set<int> newTemplates;

  /// The version a restore put into [draft], with its rules.
  final StoredRules? restoring;

  /// The server's last check, of [checked].
  final RulesCheck? check;
  final GeneratorRules? checked;
  final bool checking;
  final Failure? checkFailure;

  /// The findings of each loaded version's own rules, by version.
  final Map<int, List<Finding>> publishedFindings;
  final bool publishedChecking;
  final Failure? publishedCheckFailure;

  final PublishStatus publishStatus;
  final Failure? publishFailure;

  /// After a publish refused for the admin claim: the token was refreshed
  /// and still carries it, so publishing again may work.
  final bool accessRefreshed;

  /// The version the last publish made.
  final int? published;

  /// A publish was refused because someone else published meanwhile; until
  /// the rules are reloaded.
  final bool stale;

  final bool historyOpen;

  /// The latest versions, newest first; null until loaded.
  final List<StoredRules>? history;
  final Failure? historyFailure;

  /// The version whose rules a restore is loading.
  final int? restoreLoading;
  final Failure? restoreFailure;

  final RulesTab tab;

  /// The template open on the Templates tab, and its day.
  final int template;
  final int day;

  /// The goal the Dosing table shows.
  final String dosingGoal;

  GeneratorRules? get rules => loaded?.rules;

  /// Every change of [draft] against [rules].
  late final List<RulesChange> changes = switch ((rules, draft)) {
    (final rules?, final draft?) => rulesChanges(
      rules,
      draft,
      newTemplates: newTemplates,
    ),
    _ => const [],
  };

  bool get hasChanges => changes.isNotEmpty;

  /// The tabs with changes, in tab order.
  late final List<RulesTab> changedTabs = [
    for (final tab in RulesTab.values)
      if (changes.any((change) => tabOf(change.path) == tab)) tab,
  ];

  /// The validator's problems with the last checked draft.
  late final List<RulesProblem> problems = [
    for (final problem in check?.problems ?? const <String>[])
      RulesProblem.parse(problem),
  ];

  late final Set<RulesTab> problemTabs = {
    for (final problem in problems) ?tabOf(problem.path),
  };

  /// Whether [check] is of the draft as it is now.
  bool get draftChecked => check != null && checked == draft;

  /// Whether the draft's check is still to come: waiting for the pause
  /// after an edit, or asked.
  bool get checkDue => hasChanges && !draftChecked && checkFailure == null;

  /// The version this draft restores: a restore not edited since.
  int? get restores => switch (restoring) {
    StoredRules(:final version, :final rules) when rules == draft => version,
    _ => null,
  };

  bool get publishing => publishStatus == PublishStatus.publishing;

  /// Whether the simulator may run the draft: it differs from the loaded
  /// rules and the server checked it without problems.
  DraftCheck get draftCheck => switch (this) {
    _ when !hasChanges => DraftCheck.unchanged,
    _ when checking || !draftChecked =>
      checkFailure != null && !checking
          ? DraftCheck.unchecked
          : DraftCheck.checking,
    _ when problems.isNotEmpty => DraftCheck.problems,
    _ => DraftCheck.ready,
  };

  /// Whether the changes may be reviewed and published: the server checked
  /// this very draft and found no problem.
  bool get canPublish =>
      draft != null &&
      hasChanges &&
      draftChecked &&
      !checking &&
      problems.isEmpty &&
      !publishing;

  /// The template open on the Templates tab; null when there is none.
  int? get openTemplate =>
      template < (draft?.templates.length ?? 0) ? template : null;

  /// The open template's open day.
  int get openDay {
    final open = openTemplate;
    final days = open == null
        ? 0
        : (draft?.at(['templates', open, 'dayList']) as List?)?.length ?? 0;
    return days == 0 ? 0 : day.clamp(0, days - 1);
  }

  Object? valueAt(RulesPath path) => draft?.at(path);

  /// What [path] held in the loaded rules when the draft changed it: the
  /// "was" beside its field. Null when unchanged, or new in the draft.
  String? wasAt(RulesPath path) {
    final (draft, rules) = (this.draft, this.rules);
    if (draft == null || rules == null) return null;
    final loadedPath = loadedPathOf(
      draft,
      rules,
      path,
      newTemplates: newTemplates,
    );
    if (loadedPath == null ||
        !rules.has(loadedPath.sublist(0, loadedPath.length - 1))) {
      return null;
    }
    final before = rules.at(loadedPath);
    if (jsonEquals(before, draft.at(path))) return null;
    return valueText(path, before);
  }

  /// The messages of the problems about [field] (with [exact], about it
  /// alone).
  List<String> problemsAt(RulesPath field, {bool exact = false}) => [
    for (final problem in problems)
      if (problem.concerns(field, exact: exact)) problem.message,
  ];

  /// The findings of the loaded version's rules, once checked.
  List<Finding>? get loadedFindings => switch (loaded) {
    final loaded? => publishedFindings[loaded.version],
    null => null,
  };

  GeneratorRulesState copyWith({
    StoredRules? loaded,
    Failure? Function()? loadFailure,
    bool? loading,
    GeneratorRules? draft,
    Set<int>? newTemplates,
    StoredRules? Function()? restoring,
    RulesCheck? Function()? check,
    GeneratorRules? Function()? checked,
    bool? checking,
    Failure? Function()? checkFailure,
    Map<int, List<Finding>>? publishedFindings,
    bool? publishedChecking,
    Failure? Function()? publishedCheckFailure,
    PublishStatus? publishStatus,
    Failure? publishFailure,
    bool? accessRefreshed,
    int? published,
    bool? stale,
    bool? historyOpen,
    List<StoredRules>? history,
    Failure? Function()? historyFailure,
    int? Function()? restoreLoading,
    Failure? Function()? restoreFailure,
    RulesTab? tab,
    int? template,
    int? day,
    String? dosingGoal,
  }) => GeneratorRulesState(
    loaded: loaded ?? this.loaded,
    loadFailure: loadFailure != null ? loadFailure() : this.loadFailure,
    loading: loading ?? this.loading,
    draft: draft ?? this.draft,
    newTemplates: newTemplates ?? this.newTemplates,
    restoring: restoring != null ? restoring() : this.restoring,
    check: check != null ? check() : this.check,
    checked: checked != null ? checked() : this.checked,
    checking: checking ?? this.checking,
    checkFailure: checkFailure != null ? checkFailure() : this.checkFailure,
    publishedFindings: publishedFindings ?? this.publishedFindings,
    publishedChecking: publishedChecking ?? this.publishedChecking,
    publishedCheckFailure: publishedCheckFailure != null
        ? publishedCheckFailure()
        : this.publishedCheckFailure,
    publishStatus: publishStatus ?? this.publishStatus,
    // The outcome of a publish belongs to its status and goes with it.
    publishFailure: publishStatus == null
        ? this.publishFailure
        : publishFailure,
    accessRefreshed: publishStatus == null
        ? this.accessRefreshed
        : accessRefreshed ?? false,
    published: publishStatus == null ? this.published : published,
    stale: stale ?? this.stale,
    historyOpen: historyOpen ?? this.historyOpen,
    history: history ?? this.history,
    historyFailure: historyFailure != null
        ? historyFailure()
        : this.historyFailure,
    restoreLoading: restoreLoading != null
        ? restoreLoading()
        : this.restoreLoading,
    restoreFailure: restoreFailure != null
        ? restoreFailure()
        : this.restoreFailure,
    tab: tab ?? this.tab,
    template: template ?? this.template,
    day: day ?? this.day,
    dosingGoal: dosingGoal ?? this.dosingGoal,
  );

  @override
  List<Object?> get props => [
    loaded,
    loadFailure,
    loading,
    draft,
    newTemplates,
    restoring,
    check,
    checked,
    checking,
    checkFailure,
    publishedFindings,
    publishedChecking,
    publishedCheckFailure,
    publishStatus,
    publishFailure,
    accessRefreshed,
    published,
    stale,
    historyOpen,
    history,
    historyFailure,
    restoreLoading,
    restoreFailure,
    tab,
    template,
    day,
    dosingGoal,
  ];
}

/// The generator's rules as one draft that every tab of the page edits,
/// checked by the server a moment after each edit, published as one new
/// version after the review, and the version history with restore.
class GeneratorRulesCubit extends Cubit<GeneratorRulesState> {
  GeneratorRulesCubit({
    required this._loadGeneratorRules,
    required this._checkGeneratorRules,
    required this._publishGeneratorRules,
    required this._loadGeneratorRulesHistory,
    required this._checkAdminAccess,
  }) : super(GeneratorRulesState());

  final LoadGeneratorRules _loadGeneratorRules;
  final CheckGeneratorRules _checkGeneratorRules;
  final PublishGeneratorRules _publishGeneratorRules;
  final LoadGeneratorRulesHistory _loadGeneratorRulesHistory;
  final CheckAdminAccess _checkAdminAccess;

  /// How long after the last edit the draft is checked.
  static const checkDelay = Duration(seconds: 1);

  Timer? _checkTimer;

  /// Counts the edits and the checks asked for: only the answer to the
  /// latest check of the current draft counts.
  int _checkTurn = 0;

  @override
  Future<void> close() {
    _checkTimer?.cancel();
    return super.close();
  }

  /// Loads the current version. A draft with changes is kept, and from
  /// then on compared with the new version; one without takes its rules.
  Future<void> load() async {
    if (state.loading) return;
    emit(state.copyWith(loading: true));
    final result = await _loadGeneratorRules(null);
    if (isClosed) return;
    switch (result) {
      case Ok(value: final loaded):
        final keep = state.hasChanges ? state.draft : null;
        emit(
          GeneratorRulesState(
            loaded: loaded,
            draft: keep ?? loaded.rules,
            newTemplates: keep == null ? const {} : state.newTemplates,
            restoring: keep == null ? null : state.restoring,
            check: keep == null ? null : state.check,
            checked: keep == null ? null : state.checked,
            publishedFindings: state.publishedFindings,
            // A publish waits for this load before it says it is done.
            publishStatus: state.publishing
                ? PublishStatus.publishing
                : PublishStatus.idle,
            historyOpen: state.historyOpen,
            history: state.history,
            tab: state.tab,
            template: state.template,
            day: state.day,
            dosingGoal: state.dosingGoal,
          ),
        );
      case Err(:final failure):
        emit(state.copyWith(loading: false, loadFailure: () => failure));
    }
  }

  void selectTab(RulesTab tab) => emit(state.copyWith(tab: tab));

  void selectTemplate(int template) =>
      emit(state.copyWith(template: template, day: 0));

  void selectDay(int day) => emit(state.copyWith(day: day));

  void selectDosingGoal(String goal) => emit(state.copyWith(dosingGoal: goal));

  /// Opens the tab of [problem], with its template and day, or its goal.
  void openProblem(RulesProblem problem) {
    final tab = tabOf(problem.path);
    if (tab == null) return;
    emit(switch (problem.path) {
      ['templates', final int t, 'dayList', final int d, ...] => state.copyWith(
        tab: tab,
        template: t,
        day: d,
      ),
      ['templates', final int t, ...] => state.copyWith(
        tab: tab,
        template: t,
        day: 0,
      ),
      ['dosing', final String goal, ...] => state.copyWith(
        tab: tab,
        dosingGoal: goal,
      ),
      _ => state.copyWith(tab: tab),
    });
  }

  /// Sets [path] of the draft to [value]; null removes an object's field.
  void setValue(RulesPath path, Object? value) =>
      _edit((rules) => rules.set(path, value));

  void addItem(RulesPath list, Object? value) =>
      _edit((rules) => rules.add(list, value), structural: true);

  void removeItem(RulesPath list, int index) =>
      _edit((rules) => rules.removeAt(list, index), structural: true);

  void moveItem(RulesPath list, int from, int to) =>
      _edit((rules) => rules.move(list, from, to), structural: true);

  /// Adds a template of the open template's split (the first split when
  /// none is open) and opens it.
  void addTemplate() {
    final draft = state.draft;
    if (draft == null || state.publishing) return;
    final split = switch (state.openTemplate) {
      final open? => draft.at(['templates', open, 'split']),
      null => draft.at(['splits', 0, 'id']),
    };
    final template = draft.templates.length;
    _edit(
      (rules) => rules.add(['templates'], newTemplate(rules, split: '$split')),
      structural: true,
      newTemplates: {...state.newTemplates, template},
    );
    emit(state.copyWith(tab: RulesTab.templates, template: template, day: 0));
  }

  void removeTemplate(int template) {
    if (state.publishing) return;
    _edit(
      (rules) => rules.removeAt(['templates'], template),
      structural: true,
      newTemplates: {
        for (final t in state.newTemplates)
          if (t != template) t > template ? t - 1 : t,
      },
    );
    emit(state.copyWith(template: template == 0 ? 0 : template - 1, day: 0));
  }

  /// Sets [template]'s days a week to [days], adding days at the end or
  /// removing the last ones.
  void setDays(int template, int days) => _edit((rules) {
    final path = ['templates', template, 'dayList'];
    final count = (rules.at(path) as List?)?.length ?? 0;
    return rules
        .set(['templates', template, 'days'], days)
        .updateList(
          path,
          (list) => count > days
              ? list.sublist(0, days)
              : [...list, for (var d = count; d < days; d++) newDay(d)],
        );
  }, structural: true);

  /// Takes the draft back to the loaded rules.
  void discard() {
    final rules = state.rules;
    if (rules == null || state.publishing) return;
    _checkTimer?.cancel();
    _checkTurn++;
    emit(
      state.copyWith(
        draft: rules,
        newTemplates: const {},
        restoring: () => null,
        check: () => null,
        checked: () => null,
        checking: false,
        checkFailure: () => null,
      ),
    );
  }

  /// Applies [change] to the draft and checks it a moment later. A
  /// [structural] change (an item added, removed or moved) drops the last
  /// check at once: its problems name places that have moved.
  void _edit(
    GeneratorRules Function(GeneratorRules rules) change, {
    bool structural = false,
    Set<int>? newTemplates,
  }) {
    final draft = state.draft;
    if (draft == null || state.publishing) return;
    final edited = change(draft);
    // A check of an earlier draft is answered for nothing.
    _checkTurn++;
    _checkTimer?.cancel();
    final templates = newTemplates ?? state.newTemplates;
    final unchanged = templates.isEmpty && edited == state.rules;
    final drop = unchanged || structural;
    emit(
      state.copyWith(
        draft: edited,
        newTemplates: templates,
        // The loaded rules passed the server's check when published.
        check: drop ? () => null : null,
        checked: drop ? () => null : null,
        checking: false,
        checkFailure: () => null,
      ),
    );
    if (!unchanged) _checkTimer = Timer(checkDelay, checkDraft);
  }

  /// Checks the draft now, unless its check is current.
  Future<void> checkDraft() async {
    _checkTimer?.cancel();
    final draft = state.draft;
    if (draft == null || state.draftChecked) return;
    final turn = ++_checkTurn;
    emit(state.copyWith(checking: true, checkFailure: () => null));
    final result = await _checkGeneratorRules(draft);
    if (isClosed || turn != _checkTurn) return;
    switch (result) {
      case Ok(value: final check):
        emit(
          state.copyWith(
            check: () => check,
            checked: () => draft,
            checking: false,
          ),
        );
      case Err(:final failure):
        emit(state.copyWith(checking: false, checkFailure: () => failure));
    }
  }

  /// What the review needs: the draft checked, and the loaded version's
  /// own findings (checked once per version).
  Future<void> review() => Future.wait([checkDraft(), _checkLoaded()]);

  Future<void> _checkLoaded() async {
    final loaded = state.loaded;
    final rules = loaded?.rules;
    if (loaded == null ||
        rules == null ||
        state.publishedChecking ||
        state.publishedFindings.containsKey(loaded.version)) {
      return;
    }
    emit(
      state.copyWith(
        publishedChecking: true,
        publishedCheckFailure: () => null,
      ),
    );
    final result = await _checkGeneratorRules(rules);
    if (isClosed) return;
    switch (result) {
      case Ok(value: final check):
        emit(
          state.copyWith(
            publishedChecking: false,
            publishedFindings: {
              ...state.publishedFindings,
              loaded.version: check.findings,
            },
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            publishedChecking: false,
            publishedCheckFailure: () => failure,
          ),
        );
    }
  }

  /// Publishes the draft onto the loaded version with [note], then loads
  /// the new version (still publishing until it is in), and the history
  /// when it is open.
  Future<void> publish(String note) async {
    final (loaded, draft) = (state.loaded, state.draft);
    if (loaded == null || draft == null || !state.canPublish) return;
    emit(state.copyWith(publishStatus: PublishStatus.publishing));
    final result = await _publishGeneratorRules(
      RulesPublish(
        base: loaded.version,
        rules: draft,
        note: note.trim().isEmpty ? null : note.trim(),
        restores: state.restores,
      ),
    );
    if (isClosed) return;
    switch (result) {
      case Ok(value: final version):
        await load();
        if (isClosed) return;
        emit(
          state.copyWith(
            publishStatus: PublishStatus.published,
            published: version,
            restoring: () => null,
          ),
        );
        if (state.historyOpen) await _loadHistory();
      case Err(failure: final GeneratorRulesStaleFailure failure):
        emit(
          state.copyWith(
            publishStatus: PublishStatus.failed,
            publishFailure: failure,
            stale: true,
          ),
        );
      case Err(failure: final GeneratorRulesInvalidFailure failure):
        emit(
          state.copyWith(
            publishStatus: PublishStatus.failed,
            publishFailure: failure,
            check: () => RulesCheck(problems: failure.problems),
            checked: () => draft,
          ),
        );
      case Err(failure: final PermissionFailure failure):
        // The claim may have been revoked, or the token may just be stale:
        // a refreshed token tells.
        final access = await _checkAdminAccess(true);
        if (isClosed) return;
        emit(
          state.copyWith(
            publishStatus: PublishStatus.failed,
            publishFailure: failure,
            accessRefreshed: access.valueOrNull ?? false,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            publishStatus: PublishStatus.failed,
            publishFailure: failure,
          ),
        );
    }
  }

  /// Opens the history, loading it the first time.
  Future<void> openHistory() async {
    emit(state.copyWith(historyOpen: true));
    if (state.history == null) await _loadHistory();
  }

  void closeHistory() =>
      emit(state.copyWith(historyOpen: false, restoreFailure: () => null));

  Future<void> retryHistory() => _loadHistory();

  Future<void> _loadHistory() async {
    emit(state.copyWith(historyFailure: () => null));
    final result = await _loadGeneratorRulesHistory(const NoParams());
    if (isClosed) return;
    switch (result) {
      case Ok(value: final history):
        emit(state.copyWith(history: history));
      case Err(:final failure):
        emit(state.copyWith(historyFailure: () => failure));
    }
  }

  /// Puts [version]'s rules into the draft, so the review shows what
  /// restoring it changes and the publish says it restores it.
  Future<void> restore(int version) async {
    if (state.draft == null || state.publishing) return;
    emit(
      state.copyWith(restoreLoading: () => version, restoreFailure: () => null),
    );
    final result = await _loadGeneratorRules(version);
    if (isClosed) return;
    switch (result) {
      case Ok(value: StoredRules(rules: final rules?) && final stored):
        emit(state.copyWith(restoreLoading: () => null));
        _edit((_) => rules, structural: true, newTemplates: const {});
        emit(state.copyWith(restoring: () => stored));
      case Ok():
        emit(
          state.copyWith(
            restoreLoading: () => null,
            restoreFailure: () =>
                NotFoundFailure('version $version has no rules'),
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            restoreLoading: () => null,
            restoreFailure: () => failure,
          ),
        );
    }
  }
}
