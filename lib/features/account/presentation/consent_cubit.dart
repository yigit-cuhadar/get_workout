import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/account_usecases.dart';
import '../domain/consent_repository.dart';

class ConsentState extends Equatable {
  const ConsentState({this.stored, this.failure});

  /// The signed-in user's answer as last read; null until read.
  final StoredConsent? stored;

  /// Set when the last answer could not be saved.
  final Failure? failure;

  bool get loaded => stored != null;
  bool? get consent => stored?.consent;

  /// Time to ask: the server says the user has not answered. A cached copy
  /// without an answer may predate one given on another device.
  bool get unanswered =>
      stored?.consent == null && (stored?.fromServer ?? false);

  @override
  List<Object?> get props => [stored, failure];
}

/// App-wide: follows the signed-in user's analytics consent, guests
/// included, and applies it to collection. Collection is per user: from a
/// user change until the new user's answer is read it is off, and it stays
/// off when that read fails.
class ConsentCubit extends Cubit<ConsentState> {
  ConsentCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchConsent,
    required this._saveConsent,
    required this._followUser,
    required this._applyConsent,
  }) : super(const ConsentState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchAnalyticsConsent _watchConsent;
  final SaveAnalyticsConsent _saveConsent;
  final FollowAnalyticsUser _followUser;
  final ApplyAnalyticsConsent _applyConsent;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<StoredConsent>? _consentSubscription;
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    unawaited(_consentSubscription?.cancel());
    // Never show the previous user's answer.
    if (state != const ConsentState()) emit(const ConsentState());
    // Runs before any answer below is applied.
    unawaited(_log(_followUser(uid)));
    _consentSubscription = uid == null
        ? null
        : _watchConsent(uid).listen(
            (stored) {
              emit(ConsentState(stored: stored));
              // A cached copy without an answer changes nothing yet.
              if (stored.consent == null && !stored.fromServer) return;
              unawaited(
                _log(
                  _applyConsent((uid: uid, consent: stored.consent ?? false)),
                ),
              );
            },
            // The repository logs it; collection stays as it is.
            onError: (Object _) {},
          );
  }

  static Future<void> _log(Future<Result<void>> applying) async {
    if ((await applying).failureOrNull case final failure?) {
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
      emit(ConsentState(stored: state.stored, failure: failure));
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _consentSubscription?.cancel();
    return super.close();
  }
}
