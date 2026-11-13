import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/settings_usecases.dart';
import '../domain/user_settings.dart';

class SettingsState extends Equatable {
  const SettingsState(this.settings, {this.failure});

  final UserSettings settings;

  /// Set when the last update failed; [settings] then still hold the values
  /// from before it.
  final Failure? failure;

  @override
  List<Object?> get props => [settings, failure];
}

/// App-wide settings of whoever is signed in. Shows the device defaults until
/// the current user's stored settings arrive, also after every user change.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchSettings,
    required this._updateSettings,
    required this._defaults,
  }) : super(SettingsState(_defaults)) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchSettings _watchSettings;
  final UpdateSettings _updateSettings;

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
            (settings) => emit(SettingsState(settings)),
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
      emit(SettingsState(state.settings, failure: failure));
    }
  }

  /// Notes that [tip] needs showing no more.
  Future<void> tipSeen(Tip tip) async {
    final settings = state.settings;
    if (settings.seenTips.contains(tip)) return;
    await update(settings.copyWith(seenTips: {...settings.seenTips, tip}));
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _settingsSubscription?.cancel();
    return super.close();
  }
}
