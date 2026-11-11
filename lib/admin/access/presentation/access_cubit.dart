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
///
/// The claims are read again at every ID token change, so a claim granted or
/// revoked takes effect at the next token refresh. Such a re-check never
/// interrupts an admin: it shows no progress state, and a failed read keeps
/// the access already granted.
class AccessCubit extends Cubit<AccessState> {
  AccessCubit({
    required WatchAccessChanges watchAccessChanges,
    required this._checkAdminAccess,
    required this._signOut,
  }) : super(const AccessChecking()) {
    _subscription = watchAccessChanges().listen(_onToken);
  }

  final CheckAdminAccess _checkAdminAccess;
  final SignOut _signOut;
  late final StreamSubscription<AuthUser?> _subscription;
  AuthUser? _user;

  /// Counts checks, so only the latest one's result is used.
  int _checks = 0;

  Future<void> _onToken(AuthUser? user) async {
    _user = user;
    if (user == null) {
      _checks++;
      return emit(const SignedOut());
    }
    await _check(user, refresh: false);
  }

  /// Fetches a new ID token, so a claim granted since sign-in takes effect.
  Future<void> refreshAccess() async {
    final user = _user;
    if (user != null) await _check(user, refresh: true);
  }

  Future<Result<void>> signOut() => _signOut();

  Future<void> _check(AuthUser user, {required bool refresh}) async {
    final check = ++_checks;
    final admitted = switch (state) {
      SignedIn(user: final current, isAdmin: true) => current.id == user.id,
      _ => false,
    };
    if (!admitted) emit(const AccessChecking());
    final result = await _checkAdminAccess(refresh);
    // A sign-out, another user or a newer check while the claims were read
    // wins.
    if (isClosed || check != _checks) return;
    switch (result) {
      case Ok(value: final isAdmin):
        emit(SignedIn(user, isAdmin: isAdmin));
      case Err(:final failure) when admitted:
        Log.e('access', 'Claims re-check failed; access kept', failure);
      case Err(:final failure):
        emit(AccessCheckFailed(user, failure));
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
