import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';

import '../../body/presentation/body_list_cubit.dart';
import '../../programs/domain/calendar_date.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/measurement_prompt.dart';

/// The [measurementPrompt] of whoever is signed in, from the app's body
/// list and settings; null while either loads or nothing is due. Its date
/// moves on with [refreshNow], e.g. after the app slept over midnight.
class MeasurementPromptCubit extends Cubit<MeasurementPrompt?> {
  MeasurementPromptCubit({
    required WatchAuthUser watchAuthUser,
    required BodyListCubit bodyList,
    required SettingsCubit settings,
    required this._loadDismissed,
    required this._dismiss,
    DateTime Function()? clock,
  }) : _bodyList = bodyList,
       _settings = settings,
       _clock = clock ?? DateTime.now,
       super(null) {
    _subscriptions = [
      watchAuthUser().map((user) => user?.id).distinct().listen(_userChanged),
      bodyList.stream.listen((_) => _publish()),
      settings.stream.listen((_) => _publish()),
    ];
  }

  final BodyListCubit _bodyList;
  final SettingsCubit _settings;
  final LoadDismissedPrompt _loadDismissed;
  final DismissPrompt _dismiss;
  final DateTime Function() _clock;
  late final List<StreamSubscription<Object?>> _subscriptions;
  String? _uid;

  /// The dismissed date of [_uid], once loaded.
  CalendarDate? _dismissed;
  bool _dismissedKnown = false;

  Future<void> _userChanged(String? uid) async {
    _uid = uid;
    _dismissed = null;
    _dismissedKnown = false;
    _publish();
    if (uid == null) return;
    final result = await _loadDismissed(uid);
    if (isClosed || uid != _uid) return;
    // An unreadable file is as good as none: the prompt shows again.
    _dismissed = result.valueOrNull;
    _dismissedKnown = true;
    _publish();
  }

  void refreshNow() => _publish();

  /// Hides the prompt until the next measurement day.
  Future<void> dismiss() async {
    final (uid, prompt) = (_uid, state);
    if (uid == null || prompt == null) return;
    _dismissed = prompt.date;
    _publish();
    await _dismiss((uid: uid, date: prompt.date));
  }

  void _publish() {
    final body = _bodyList.state;
    final settings = _settings.state;
    if (isClosed) return;
    emit(
      _uid == null ||
              !_dismissedKnown ||
              !settings.loaded ||
              body.status != BodyListStatus.ready
          ? null
          : measurementPrompt(
              settings.settings.measurementReminder,
              body.entries,
              today: CalendarDate.of(_clock()),
              dismissed: _dismissed,
            ),
    );
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
