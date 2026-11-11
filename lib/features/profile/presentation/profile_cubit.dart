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
    this.writeRejected = false,
  });

  /// Whose profile this is; null while nobody is signed in.
  final String? uid;
  final ProfileStatus status;
  final UserProfile profile;

  /// A save was rejected after its page had closed; shown once, then
  /// cleared with [ProfileCubit.rejectionShown].
  final bool writeRejected;

  @override
  List<Object?> get props => [uid, status, profile, writeRejected];
}

/// App-wide profile of whoever is signed in. Starts over, empty and loading,
/// on every user change, so the previous user's answers are never shown. A
/// failed read is retried with backoff; a profile already shown stays
/// meanwhile.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required WatchAuthUser watchAuthUser,
    required WatchProfile watchProfile,
    required this._updateProfile,
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
          writeRejected: state.writeRejected,
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

  final UpdateProfile _updateProfile;
  late final UserStreamFollower<UserProfile> _follower;

  /// Saves [fields] of [profile] for the current user. The change shows up
  /// through the profile stream at once, from Firestore's local cache, so
  /// pages do not wait for this; a rejection, possibly much later, sets
  /// [ProfileState.writeRejected].
  Future<void> save(UserProfile profile, Set<ProfileField> fields) async {
    final uid = _follower.uid;
    if (uid == null) return;
    resume();
    final result = await _updateProfile((
      uid: uid,
      profile: profile,
      fields: fields,
    ));
    // A rejection for a previous user says nothing about the current one.
    if (result.isOk || isClosed || _follower.uid != uid) return;
    emit(
      ProfileState(
        uid: uid,
        status: state.status,
        profile: state.profile,
        writeRejected: true,
      ),
    );
  }

  void rejectionShown() {
    if (!state.writeRejected) return;
    emit(
      ProfileState(
        uid: state.uid,
        status: state.status,
        profile: state.profile,
      ),
    );
  }

  /// Follows the profile again at once if its stream failed. Call when
  /// saving, so the saved answers show up.
  void resume() => _follower.resume();

  @override
  Future<void> close() async {
    await _follower.cancel();
    return super.close();
  }
}
