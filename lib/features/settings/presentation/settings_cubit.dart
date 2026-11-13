import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/settings_usecases.dart';
import '../domain/user_settings.dart';

class SettingsState extends Equatable {
  const SettingsState(this.settings, {this.failure, this.loaded = false});

  final UserSettings settings;

  /// The signed-in user's own settings have arrived; until then [settings]
  /// are the device defaults, and no first-use tip shows.
  final bool loaded;

  /// Set when the last update failed; [settings] then still hold the values
  /// from before it.
  final Failure? failure;

  @override
  List<Object?> get props => [settings, failure, loaded];
}

/// App-wide settings of whoever is signed in. Shows the device defaults until
/// the current user's stored settings arrive, also after every user change.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchSettings,
    required this._updateSettings,
    required this._markTipSeen,
    required this._defaults,
  }) : super(SettingsState(_defaults)) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchSettings _watchSettings;
  final UpdateSettings _updateSettings;
  final MarkTipSeen _markTipSeen;

  /// Shown, and the base for updates, until a user's own settings arrive.
  final UserSettings _defaults;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<UserSettings>? _settingsSubscription;
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    unawaited(_settingsSubscription?.cancel());
    // Never show, or build an update on, the previous user's settings.
    final reset = SettingsState(_defaults);
    if (state != reset) emit(reset);
    _settingsSubscription = uid == null
        ? null
        : _watchSettings(uid).listen(
            (settings) => emit(SettingsState(settings, loaded: true)),
            // The repository logs it; the last known settings stay in use.
            onError: (Object _) {},
          );
  }

  /// The change shows up through the settings stream (immediately, from
  /// Firestore's local cache); only a failure is emitted here.
  Future<void> update(UserSettings settings) async {
    final uid = _uid;
    if (uid == null || settings == state.settings) return;
    final result = await _updateSettings((uid: uid, settings: settings));
    final failure = result.failureOrNull;
    if (failure != null && !isClosed) {
      emit(
        SettingsState(state.settings, failure: failure, loaded: state.loaded),
      );
    }
  }

  /// Notes that [tip] needs showing no more, once the user's settings are
  /// known; it shows up through the settings stream.
  Future<void> tipSeen(Tip tip) async {
    final uid = _uid;
    if (uid == null || !state.loaded) return;
    if (state.settings.seenTips.contains(tip)) return;
    final result = await _markTipSeen((uid: uid, tip: tip));
    final failure = result.failureOrNull;
    if (failure != null && !isClosed) {
      emit(
        SettingsState(state.settings, failure: failure, loaded: state.loaded),
      );
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _settingsSubscription?.cancel();
    return super.close();
  }
}
