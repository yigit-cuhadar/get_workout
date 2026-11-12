import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/account_usecases.dart';

class ConsentState extends Equatable {
  const ConsentState({this.loaded = false, this.consent, this.failure});

  /// Whether the signed-in user's answer has been read.
  final bool loaded;

  /// Null until the user has answered.
  final bool? consent;

  /// Set when the last answer could not be saved.
  final Failure? failure;

  /// Time to ask: the user's answer is known to be missing.
  bool get unanswered => loaded && consent == null;

  @override
  List<Object?> get props => [loaded, consent, failure];
}

/// App-wide: follows the signed-in user's analytics consent, guests
/// included, and applies it to collection whenever it arrives or changes.
/// Until a user's own answer is read, the device keeps what it applied
/// last.
class ConsentCubit extends Cubit<ConsentState> {
  ConsentCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchConsent,
    required this._saveConsent,
    required this._applyConsent,
  }) : super(const ConsentState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchAnalyticsConsent _watchConsent;
  final SaveAnalyticsConsent _saveConsent;
  final ApplyAnalyticsConsent _applyConsent;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<bool?>? _consentSubscription;
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    unawaited(_consentSubscription?.cancel());
    // Never show the previous user's answer.
    if (state != const ConsentState()) emit(const ConsentState());
    _consentSubscription = uid == null
        ? null
        : _watchConsent(uid).distinct().listen(
            (consent) {
              emit(ConsentState(loaded: true, consent: consent));
              unawaited(_apply(consent));
            },
            // The repository logs it; collection stays as it was.
            onError: (Object _) {},
          );
  }

  Future<void> _apply(bool? consent) async {
    if ((await _applyConsent(consent)).failureOrNull case final failure?) {
      Log.e('consent', 'not applied: ${failure.message}');
    }
  }

  /// Applied through the consent stream, which Firestore's local cache
  /// answers at once; only a failure is emitted here.
  Future<void> answer(bool consent) async {
    final uid = _uid;
    if (uid == null) return;
    final result = await _saveConsent((uid: uid, consent: consent));
    if (result.failureOrNull case final failure? when !isClosed) {
      emit(
        ConsentState(
          loaded: state.loaded,
          consent: state.consent,
          failure: failure,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _consentSubscription?.cancel();
    return super.close();
  }
}
