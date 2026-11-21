import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../access/domain/access_usecases.dart';
import '../domain/app_settings.dart';
import '../domain/app_settings_usecases.dart';

enum PublishStatus {
  idle,
  publishing,

  /// The last publish went through ([AppSettingsState.published]).
  published,
  failed,
}

class AppSettingsState extends Equatable {
  const AppSettingsState({
    this.settings,
    this.loadFailure,
    this.loading = false,
    this.edits = const {},
    this.formVersion = 0,
    this.publishStatus = PublishStatus.idle,
    this.publishFailure,
    this.accessRefreshed = false,
    this.published,
    this.historyOpen = false,
    this.history,
    this.historyFailure,
    this.openedVersion,
  });

  /// Null until first loaded.
  final AppSettings? settings;

  /// Why the last load failed; [settings] keeps the last loaded.
  final Failure? loadFailure;
  final bool loading;

  /// The new value of each changed key, as Remote Config sends it; a key
  /// set back to its value leaves.
  final Map<String, String> edits;

  /// Changes when the fields must show [edits] and [settings] afresh (a
  /// load or a discard), so they rebuild.
  final int formVersion;

  final PublishStatus publishStatus;

  /// Why the last publish failed, with [PublishStatus.failed].
  final Failure? publishFailure;

  /// After a publish refused for the admin claim: the token was refreshed
  /// and still carries it, so publishing again may work.
  final bool accessRefreshed;

  /// The version the last publish made, with [PublishStatus.published].
  final ConfigVersion? published;

  final bool historyOpen;

  /// The latest versions, newest first; null until loaded.
  final List<VersionEntry>? history;
  final Failure? historyFailure;

  /// The version opened in the history, showing what restoring changes.
  final int? openedVersion;

  /// The value [key]'s field shows.
  String? valueOf(String key) =>
      edits[key] ??
      switch (settings) {
        final settings? => specOf(key).effective(settings.settingOf(key).value),
        null => null,
      };

  /// The edits as changes, in page order.
  List<SettingChange> get changes => [
    for (final spec in settingSpecs)
      if (edits[spec.key] case final value?)
        SettingChange(
          spec.key,
          before: settings?.settingOf(spec.key).value ?? const AppDefault(),
          after: SetValue(value),
        ),
  ];

  /// Why [key]'s edited value cannot be published, or null.
  String? problemOf(String key) => switch (edits[key]) {
    final value? => specOf(key).problem(value),
    null => null,
  };

  bool get publishing => publishStatus == PublishStatus.publishing;

  bool get canPublish =>
      settings != null &&
      !publishing &&
      edits.isNotEmpty &&
      edits.keys.every((key) => problemOf(key) == null);

  AppSettingsState copyWith({
    AppSettings? settings,
    Failure? Function()? loadFailure,
    bool? loading,
    Map<String, String>? edits,
    int? formVersion,
    PublishStatus? publishStatus,
    Failure? publishFailure,
    bool? accessRefreshed,
    ConfigVersion? published,
    bool? historyOpen,
    List<VersionEntry>? history,
    Failure? Function()? historyFailure,
    int? Function()? openedVersion,
  }) => AppSettingsState(
    settings: settings ?? this.settings,
    loadFailure: loadFailure != null ? loadFailure() : this.loadFailure,
    loading: loading ?? this.loading,
    edits: edits ?? this.edits,
    formVersion: formVersion ?? this.formVersion,
    publishStatus: publishStatus ?? this.publishStatus,
    // The outcome of a publish belongs to its status and goes with it.
    publishFailure: publishStatus == null
        ? this.publishFailure
        : publishFailure,
    accessRefreshed: publishStatus == null
        ? this.accessRefreshed
        : accessRefreshed ?? false,
    published: publishStatus == null ? this.published : published,
    historyOpen: historyOpen ?? this.historyOpen,
    history: history ?? this.history,
    historyFailure: historyFailure != null
        ? historyFailure()
        : this.historyFailure,
    openedVersion: openedVersion != null ? openedVersion() : this.openedVersion,
  );

  @override
  List<Object?> get props => [
    settings,
    loadFailure,
    loading,
    edits,
    formVersion,
    publishStatus,
    publishFailure,
    accessRefreshed,
    published,
    historyOpen,
    history,
    historyFailure,
    openedVersion,
  ];
}

/// The app's Remote Config keys edited in place, published as one new
/// version after the page's confirm, and the version history with
/// restore. One publish at a time.
class AppSettingsCubit extends Cubit<AppSettingsState> {
  AppSettingsCubit({
    required this._loadAppSettings,
    required this._loadSettingsHistory,
    required this._publishAppSettings,
    required this._checkAdminAccess,
  }) : super(const AppSettingsState());

  final LoadAppSettings _loadAppSettings;
  final LoadSettingsHistory _loadSettingsHistory;
  final PublishAppSettings _publishAppSettings;
  final CheckAdminAccess _checkAdminAccess;

  /// Loads the current version. Edits survive: those equal to the new
  /// values, or of a key the console now owns, leave; the rest stay
  /// changes against the new values.
  Future<void> load() async {
    if (state.loading) return;
    emit(state.copyWith(loading: true));
    final result = await _loadAppSettings(const NoParams());
    if (isClosed) return;
    switch (result) {
      case Ok(value: final settings):
        emit(
          state.copyWith(
            settings: settings,
            loading: false,
            loadFailure: () => null,
            edits: {
              for (final MapEntry(:key, :value) in state.edits.entries)
                if (specOf(key).effective(settings.settingOf(key).value)
                    case final current? when current != value)
                  key: value,
            },
            formVersion: state.formVersion + 1,
          ),
        );
      case Err(:final failure):
        emit(state.copyWith(loading: false, loadFailure: () => failure));
    }
  }

  /// Sets [key]'s new value; its current value takes the change back.
  void edit(String key, String value) {
    final settings = state.settings;
    if (settings == null || state.publishing) return;
    final current = specOf(key).effective(settings.settingOf(key).value);
    // A key the console owns has no field.
    if (current == null) return;
    final edits = {...state.edits}..remove(key);
    if (value != current) edits[key] = value;
    emit(state.copyWith(edits: edits, publishStatus: PublishStatus.idle));
  }

  void discard() {
    if (state.publishing) return;
    emit(
      state.copyWith(
        edits: const {},
        formVersion: state.formVersion + 1,
        publishStatus: PublishStatus.idle,
      ),
    );
  }

  /// Publishes [changes] (the edits, or a restore's) onto the loaded
  /// version; [restoring] names the version a restore brings back. Then
  /// loads the new version, and the history when it is open.
  Future<void> publish(List<SettingChange> changes, {int? restoring}) async {
    final settings = state.settings;
    if (settings == null || state.publishing) return;
    emit(state.copyWith(publishStatus: PublishStatus.publishing));
    final result = await _publishAppSettings(
      SettingsPublish(
        etag: settings.etag,
        changes: changes,
        restoring: restoring,
      ),
    );
    if (isClosed) return;
    switch (result) {
      case Ok(value: final version):
        emit(
          state.copyWith(
            publishStatus: PublishStatus.published,
            published: version,
            openedVersion: () => null,
          ),
        );
        await load();
        if (state.historyOpen) await _loadHistory();
      case Err(failure: final PermissionFailure failure):
        // The claim may have been revoked, or the token may just be stale:
        // a refreshed token tells. Without the claim, the access gate (which
        // follows token changes) leaves this page.
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
      emit(state.copyWith(historyOpen: false, openedVersion: () => null));

  Future<void> retryHistory() => _loadHistory();

  /// Opens [number] in the history, or closes the open one with null.
  void openVersion(int? number) =>
      emit(state.copyWith(openedVersion: () => number));

  Future<void> _loadHistory() async {
    emit(state.copyWith(historyFailure: () => null));
    final result = await _loadSettingsHistory(const NoParams());
    if (isClosed) return;
    switch (result) {
      case Ok(value: final history):
        emit(state.copyWith(history: history));
      case Err(:final failure):
        emit(state.copyWith(historyFailure: () => failure));
    }
  }
}
