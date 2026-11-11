import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../domain/profile_usecases.dart';
import '../domain/user_profile.dart';

enum ProfileStatus {
  /// The first snapshot of [ProfileState.uid]'s profile has not arrived.
  loading,
  loaded,

  /// The first read failed. It is retried; the app carries on meanwhile.
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
/// on every user change, so the previous user's answers are never shown. A
/// failed read is retried with backoff; a profile already shown stays
/// meanwhile.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required WatchAuthUser watchAuthUser,
    required WatchProfile watchProfile,
    Duration retryDelay = const Duration(seconds: 1),
  }) : super(const ProfileState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchProfile.call,
      onUser: (uid) {
        final reset = ProfileState(uid: uid);
        if (state != reset) emit(reset);
      },
      onData: (profile) => emit(
        ProfileState(
          uid: _follower.uid,
          status: ProfileStatus.loaded,
          profile: profile,
        ),
      ),
      onError: (_) {
        if (state.status == ProfileStatus.loading) {
          emit(ProfileState(uid: state.uid, status: ProfileStatus.unavailable));
        }
      },
      logTag: 'profile',
      retryDelay: retryDelay,
    );
  }

  late final UserStreamFollower<UserProfile> _follower;

  /// Follows the profile again at once if its stream failed. Call when
  /// saving, so the saved answers show up.
  void resume() => _follower.resume();

  @override
  Future<void> close() async {
    await _follower.cancel();
    return super.close();
  }
}
