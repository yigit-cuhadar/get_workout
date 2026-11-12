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

/// One deletion, from the delete page.
class DeleteAccountCubit extends Cubit<DeleteAccountState> {
  DeleteAccountCubit({
    required this._getCurrentUser,
    required this._deleteAccount,
    required this._reauthenticate,
  }) : super(const DeleteAccountState(DeleteStatus.idle));

  final GetCurrentUser _getCurrentUser;
  final DeleteUserAccount _deleteAccount;
  final Reauthenticate _reauthenticate;

  Future<void> delete() async {
    if (state.status == DeleteStatus.deleting) return;
    emit(const DeleteAccountState(DeleteStatus.deleting));
    await _delete();
  }

  Future<void> _delete() async {
    final uid = _getCurrentUser()?.id;
    final failure = uid == null
        ? const AuthFailure('nobody signed in')
        : (await _deleteAccount(uid)).failureOrNull;
    if (isClosed) return;
    emit(switch (failure) {
      null => const DeleteAccountState(DeleteStatus.done),
      AuthFailure(code: recentLoginRequiredCode) => const DeleteAccountState(
        DeleteStatus.needsPassword,
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
    if (state.status == DeleteStatus.deleting) return;
    emit(const DeleteAccountState(DeleteStatus.idle));
  }
}
