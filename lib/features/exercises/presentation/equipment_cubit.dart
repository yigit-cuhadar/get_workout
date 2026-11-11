import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise_usecases.dart';
import '../domain/vocabulary.dart';

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
    required this._watchEquipment,
    required this._saveEquipment,
  }) : super(const EquipmentState(null)) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchOwnedEquipment _watchEquipment;
  final SaveOwnedEquipment _saveEquipment;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<Set<Equipment>?>? _equipmentSubscription;
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    unawaited(_equipmentSubscription?.cancel());
    // Never show the previous user's equipment.
    const reset = EquipmentState(null);
    if (state != reset) emit(reset);
    _equipmentSubscription = uid == null
        ? null
        : _watchEquipment(uid).listen(
            (owned) => emit(EquipmentState(owned)),
            // The repository logs it; the last known equipment stays.
            onError: (Object _) {},
          );
  }

  /// The change shows up through the equipment stream (immediately, from
  /// Firestore's local cache); only a failure is emitted here.
  Future<void> save(Set<Equipment> owned) async {
    final uid = _uid;
    if (uid == null) return;
    final result = await _saveEquipment((uid: uid, equipment: owned));
    final failure = result.failureOrNull;
    if (failure != null && !isClosed) {
      emit(EquipmentState(state.owned, failure: failure));
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _equipmentSubscription?.cancel();
    return super.close();
  }
}
