import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/access_usecases.dart';

sealed class AccessState extends Equatable {
  const AccessState();

  @override
  List<Object?> get props => [];
}

/// The session or its claims are being read.
final class AccessChecking extends AccessState {
  const AccessChecking();
}

final class SignedOut extends AccessState {
  const SignedOut();
}

/// Signed in, with or without the admin claim.
final class SignedIn extends AccessState {
  const SignedIn(this.user, {required this.isAdmin});

  final AuthUser user;
  final bool isAdmin;

  @override
  List<Object?> get props => [user, isAdmin];
}

/// The claims could not be read; `refreshAccess` tries again.
final class AccessCheckFailed extends AccessState {
  const AccessCheckFailed(this.user, this.failure);

  final AuthUser user;
  final Failure failure;

  @override
  List<Object?> get props => [user, failure];
}

/// Who uses the panel and whether they may edit. Routes follow this state.
class AccessCubit extends Cubit<AccessState> {
  AccessCubit({
    required WatchAuthUser watchAuthUser,
    required this._checkAdminAccess,
    required this._signOut,
  }) : super(const AccessChecking()) {
    _subscription = watchAuthUser()
        .distinct((a, b) => a?.id == b?.id)
        .listen(_onUser);
  }

  final CheckAdminAccess _checkAdminAccess;
  final SignOut _signOut;
  late final StreamSubscription<AuthUser?> _subscription;
  AuthUser? _user;

  Future<void> _onUser(AuthUser? user) async {
    _user = user;
    if (user == null) return emit(const SignedOut());
    await _check(user, refresh: false);
  }

  /// Fetches a new ID token, so a claim granted since sign-in takes effect.
  Future<void> refreshAccess() async {
    final user = _user;
    if (user != null) await _check(user, refresh: true);
  }

  Future<Result<void>> signOut() => _signOut();

  Future<void> _check(AuthUser user, {required bool refresh}) async {
    emit(const AccessChecking());
    final result = await _checkAdminAccess(refresh);
    // A sign-out or another user while the claims were read wins.
    if (isClosed || _user != user) return;
    emit(
      result.fold(
        (isAdmin) => SignedIn(user, isAdmin: isAdmin),
        (failure) => AccessCheckFailed(user, failure),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
