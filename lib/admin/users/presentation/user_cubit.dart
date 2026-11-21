import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/admin_user.dart';
import '../domain/user_admin_usecases.dart';

/// What the actions panel did last.
enum UserAction {
  grantPremium,
  revokePremium,
  sendPasswordReset,
  makeAdmin,
  removeAdmin,
  delete,
}

class UserState extends Equatable {
  const UserState({
    this.user,
    this.failure,
    this.running,
    this.done,
    this.actionFailure,
  });

  /// Null until loaded.
  final UserDetail? user;

  /// Why the user did not load.
  final Failure? failure;

  /// The action underway; one at a time.
  final UserAction? running;

  /// The last action that went through; [UserAction.delete] means the
  /// account is gone.
  final UserAction? done;

  /// Why the last action failed.
  final Failure? actionFailure;

  @override
  List<Object?> get props => [user, failure, running, done, actionFailure];
}

/// A user's page: what Auth, Firestore and RevenueCat know of them, and
/// the actions panel. After an action that changes them, the user is read
/// again.
class UserCubit extends Cubit<UserState> {
  UserCubit({
    required this.uid,
    required this._getAdminUser,
    required this._grantPremium,
    required this._revokePremium,
    required this._sendPasswordReset,
    required this._setUserAdmin,
    required this._deleteUserAccount,
  }) : super(const UserState());

  final String uid;
  final GetAdminUser _getAdminUser;
  final GrantPromotionalPremium _grantPremium;
  final RevokePromotionalPremium _revokePremium;
  final SendPasswordReset _sendPasswordReset;
  final SetUserAdmin _setUserAdmin;
  final DeleteUserAccount _deleteUserAccount;

  Future<void> load() async {
    emit(
      UserState(
        user: state.user,
        running: state.running,
        done: state.done,
        actionFailure: state.actionFailure,
      ),
    );
    final result = await _getAdminUser(uid);
    if (isClosed) return;
    emit(
      UserState(
        user: result.valueOrNull ?? state.user,
        failure: result.failureOrNull,
        done: state.done,
        actionFailure: state.actionFailure,
      ),
    );
  }

  Future<void> grantPremium(PremiumDuration duration) => _run(
    UserAction.grantPremium,
    () => _grantPremium((uid: uid, duration: duration)),
  );

  Future<void> revokePremium() =>
      _run(UserAction.revokePremium, () => _revokePremium(uid));

  /// Sends Firebase's password reset email to the user's address.
  Future<void> sendPasswordReset() async {
    final email = state.user?.email;
    if (email == null) return;
    await _run(
      UserAction.sendPasswordReset,
      () => _sendPasswordReset(email),
      reload: false,
    );
  }

  Future<void> setAdmin({required bool admin}) => _run(
    admin ? UserAction.makeAdmin : UserAction.removeAdmin,
    () => _setUserAdmin((uid: uid, admin: admin)),
  );

  Future<void> delete() =>
      _run(UserAction.delete, () => _deleteUserAccount(uid), reload: false);

  Future<void> _run<T>(
    UserAction action,
    Future<Result<T>> Function() work, {
    bool reload = true,
  }) async {
    if (state.running != null || state.user == null) return;
    emit(UserState(user: state.user, running: action));
    final result = await work();
    if (isClosed) return;
    emit(
      UserState(
        user: state.user,
        done: result.isOk ? action : null,
        actionFailure: result.failureOrNull,
      ),
    );
    if (result.isOk && reload) await load();
  }
}
