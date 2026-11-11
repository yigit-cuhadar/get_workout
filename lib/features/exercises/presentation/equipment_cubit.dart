import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise_usecases.dart';
import '../domain/vocabulary.dart';
import '../../../core/user_stream_follower.dart';

class EquipmentState extends Equatable {
  const EquipmentState(this.owned, {this.failure});

  /// The equipment the user owns, without bodyweight; null until they have
  /// chosen.
  final Set<Equipment>? owned;

  /// Set when the last save failed; [owned] then still holds the values from
  /// before it.
  final Failure? failure;

  @override
  List<Object?> get props => [owned, failure];
}

/// The equipment of whoever is signed in. Unknown (null) until the current
/// user's choice arrives, also after every user change.
class EquipmentCubit extends Cubit<EquipmentState> {
  EquipmentCubit({
    required WatchAuthUser watchAuthUser,
    required WatchOwnedEquipment watchEquipment,
    required this._saveEquipment,
    Duration retryDelay = const Duration(seconds: 1),
  }) : super(const EquipmentState(null)) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchEquipment.call,
      // Never show the previous user's equipment.
      onUser: (_) {
        const reset = EquipmentState(null);
        if (state != reset) emit(reset);
      },
      onData: (owned) => emit(EquipmentState(owned)),
      logTag: 'equipment',
      retryDelay: retryDelay,
    );
  }

  final SaveOwnedEquipment _saveEquipment;
  late final UserStreamFollower<Set<Equipment>?> _follower;

  /// The change shows up through the equipment stream (immediately, from
  /// Firestore's local cache); only a failure is emitted here.
  Future<void> save(Set<Equipment> owned) async {
    final uid = _follower.uid;
    if (uid == null) return;
    _follower.resume();
    final result = await _saveEquipment((uid: uid, equipment: owned));
    // A write for a previous user says nothing about the current one.
    if (isClosed || _follower.uid != uid) return;
    if (result.failureOrNull case final failure?) {
      emit(EquipmentState(state.owned, failure: failure));
    }
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    return super.close();
  }
}
