import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/account_repository.dart';
import '../domain/account_usecases.dart';

enum DeleteStatus {
  idle,
  deleting,

  /// The server wants a recent sign-in; the password is asked.
  needsPassword,
  failed,

  /// The data is gone but the sign-in is not; only deleting again is
  /// offered.
  partlyDeleted,

  /// Deleted and signed out; the app moves on to a new guest by itself.
  done,
}

class DeleteAccountState extends Equatable {
  const DeleteAccountState(this.status, {this.failure});

  final DeleteStatus status;

  /// Why the last attempt failed, also a wrong password on
  /// [DeleteStatus.needsPassword].
  final Failure? failure;

  @override
  List<Object?> get props => [status, failure];
}

/// True from the start of a deletion until it ends with the user signed
/// out or nothing deleted. Meanwhile the router keeps the user where they
/// are: the vanished profile must not open onboarding, which would write
/// the deleted user's document again.
class DeletionUnderway extends ValueNotifier<bool> {
  DeletionUnderway() : super(false);
}

/// One deletion, from the delete page.
class DeleteAccountCubit extends Cubit<DeleteAccountState> {
  DeleteAccountCubit({
    required this._getCurrentUser,
    required this._deleteAccount,
    required this._reauthenticate,
    required this._underway,
    required this._releaseWorkouts,
    required this._resumeWorkouts,
  }) : super(const DeleteAccountState(DeleteStatus.idle));

  final GetCurrentUser _getCurrentUser;
  final DeleteUserAccount _deleteAccount;
  final Reauthenticate _reauthenticate;
  final DeletionUnderway _underway;

  /// Stops the workout in progress from writing for the user, and starts
  /// it again when nothing was deleted.
  final Future<void> Function(String uid) _releaseWorkouts;
  final Future<void> Function() _resumeWorkouts;

  Future<void> delete() async {
    if (state.status case DeleteStatus.deleting || DeleteStatus.done) return;
    emit(const DeleteAccountState(DeleteStatus.deleting));
    await _delete();
  }

  Future<void> _delete() async {
    final uid = _getCurrentUser()?.id;
    if (uid == null) {
      return emit(
        const DeleteAccountState(
          DeleteStatus.failed,
          failure: AuthFailure('nobody signed in'),
        ),
      );
    }
    _underway.value = true;
    await _releaseWorkouts(uid);
    final failure = (await _deleteAccount(uid)).failureOrNull;
    if (failure is! PartlyDeletedFailure) {
      if (failure != null) await _resumeWorkouts();
      _underway.value = false;
    }
    if (isClosed) return;
    emit(switch (failure) {
      null => const DeleteAccountState(DeleteStatus.done),
      AuthFailure(code: recentLoginRequiredCode) => const DeleteAccountState(
        DeleteStatus.needsPassword,
      ),
      PartlyDeletedFailure() => DeleteAccountState(
        DeleteStatus.partlyDeleted,
        failure: failure,
      ),
      _ => DeleteAccountState(DeleteStatus.failed, failure: failure),
    });
  }

  /// Signs in again with [password], then deletes.
  Future<void> confirmPassword(String password) async {
    if (state.status != DeleteStatus.needsPassword) return;
    emit(const DeleteAccountState(DeleteStatus.deleting));
    final failure = (await _reauthenticate(password)).failureOrNull;
    if (isClosed) return;
    if (failure != null) {
      return emit(
        DeleteAccountState(DeleteStatus.needsPassword, failure: failure),
      );
    }
    await _delete();
  }

  /// Back from the password prompt without deleting.
  void cancel() {
    if (state.status != DeleteStatus.needsPassword) return;
    emit(const DeleteAccountState(DeleteStatus.idle));
  }
}
