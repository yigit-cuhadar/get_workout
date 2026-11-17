import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/account_usecases.dart';

enum SyncStatus { checking, backedUp, waiting }

/// Whether this device's writes are on the server, for the Account page.
class SyncStatusCubit extends Cubit<SyncStatus> {
  SyncStatusCubit({required WatchBackedUp watchBackedUp})
    : super(SyncStatus.checking) {
    _subscription = watchBackedUp().listen(
      (backedUp) => emit(backedUp ? SyncStatus.backedUp : SyncStatus.waiting),
    );
  }

  late final StreamSubscription<bool> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
