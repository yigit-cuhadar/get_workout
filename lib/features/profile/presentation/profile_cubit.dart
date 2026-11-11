import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/profile_usecases.dart';
import '../domain/user_profile.dart';

enum ProfileStatus {
  /// The first snapshot of [ProfileState.uid]'s profile has not arrived.
  loading,
  loaded,

  /// The profile could not be read; the app carries on without it.
  unavailable,
}

class ProfileState extends Equatable {
  const ProfileState({
    this.uid,
    this.status = ProfileStatus.loading,
    this.profile = const UserProfile(),
  });

  /// Whose profile this is; null while nobody is signed in.
  final String? uid;
  final ProfileStatus status;
  final UserProfile profile;

  @override
  List<Object?> get props => [uid, status, profile];
}

/// App-wide profile of whoever is signed in. Starts over, empty and loading,
/// on every user change, so the previous user's answers are never shown.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchProfile,
  }) : super(const ProfileState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchProfile _watchProfile;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<UserProfile>? _profileSubscription;

  void _onUser(String? uid) {
    unawaited(_profileSubscription?.cancel());
    final reset = ProfileState(uid: uid);
    if (state != reset) emit(reset);
    _profileSubscription = uid == null
        ? null
        : _watchProfile(uid).listen(
            (profile) => emit(
              ProfileState(
                uid: uid,
                status: ProfileStatus.loaded,
                profile: profile,
              ),
            ),
            // The repository logs it. A profile already shown stays.
            onError: (Object _) {
              if (state.status == ProfileStatus.loading) {
                emit(ProfileState(uid: uid, status: ProfileStatus.unavailable));
              }
            },
          );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _profileSubscription?.cancel();
    return super.close();
  }
}
