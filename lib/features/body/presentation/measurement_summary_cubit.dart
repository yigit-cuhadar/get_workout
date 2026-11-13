import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../profile/domain/profile_usecases.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/body_entry.dart';
import '../domain/body_usecases.dart';
import '../domain/measurement_summary.dart';

enum MeasurementSummaryStatus {
  loading,
  ready,
  failure,

  /// The entry does not exist (any more).
  notFound,

  /// Choosing the later day: there are fewer than two measurement days.
  nothingToCompare,
}

class MeasurementSummaryState extends Equatable {
  const MeasurementSummaryState({
    this.status = MeasurementSummaryStatus.loading,
    this.summary,
    this.baseline = const PreviousDay(),
    this.candidates = const [],
    this.laterCandidates = const [],
    this.pose,
    this.photoFiles = const {},
  });

  final MeasurementSummaryStatus status;

  /// Set while [status] is ready.
  final MeasurementSummary? summary;

  /// What the entry is compared with.
  final Baseline baseline;

  /// The earlier measurement days it can be compared with, newest first.
  final List<BodyEntry> candidates;

  /// While choosing the later day, the days it can be: see
  /// [comparableDays].
  final List<BodyEntry> laterCandidates;

  /// The pose the photos show; null when neither entry has a photo.
  final PhotoPose? pose;

  /// The files of the shown photos on this device, by storage path.
  final Map<String, String> photoFiles;

  @override
  List<Object?> get props => [
    status,
    summary,
    baseline,
    candidates,
    laterCandidates,
    pose,
    photoFiles,
  ];
}

/// One measurement day of whoever is signed in compared with an earlier
/// one, both followed live with the profile (body fat, target weight):
/// the previous measurement day unless another [Baseline] is chosen. The
/// later day is the entry `afterId`; without one it can be chosen
/// ([chooseAfter]), and is otherwise, or once the chosen one is gone, the
/// newest of [comparableDays]. The photos of the chosen pose are fetched
/// from the backup when not on this device.
class MeasurementSummaryCubit extends Cubit<MeasurementSummaryState> {
  MeasurementSummaryCubit({
    required this._afterId,
    required WatchAuthUser watchAuthUser,
    required WatchBodyEntries watchEntries,
    required WatchProfile watchProfile,
    required this._findBaseline,
    required this._restorePhoto,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const MeasurementSummaryState()) {
    _entriesFollower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchEntries.call,
      onUser: (_) {
        _entries = null;
        _photoFiles = const {};
        emit(MeasurementSummaryState(baseline: _baseline, pose: _pose));
      },
      onData: (entries) {
        _entries = entries;
        _publish();
      },
      onError: (_) {
        _entries = null;
        emit(
          MeasurementSummaryState(
            status: MeasurementSummaryStatus.failure,
            baseline: _baseline,
            pose: _pose,
          ),
        );
      },
      logTag: 'body',
    );
    _profileFollower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchProfile.call,
      onUser: (_) => _profile = null,
      onData: (profile) {
        _profile = profile;
        _publish();
      },
      // Without a profile the rest still shows.
      onError: (_) {
        _profile ??= const UserProfile();
        _publish();
      },
      logTag: 'body',
    );
  }

  final String? _afterId;
  final FindBaseline _findBaseline;
  final RestoreBodyPhoto _restorePhoto;
  final DateTime Function() _clock;
  late final UserStreamFollower<List<BodyEntry>> _entriesFollower;
  late final UserStreamFollower<UserProfile> _profileFollower;
  final _restoring = <String>{};
  List<BodyEntry>? _entries;
  UserProfile? _profile;
  Baseline _baseline = const PreviousDay();
  String? _chosenAfter;
  PhotoPose? _pose;
  Map<String, String> _photoFiles = const {};

  void retry() {
    _entriesFollower.resume();
    _profileFollower.resume();
  }

  void chooseBaseline(Baseline baseline) {
    _baseline = baseline;
    _publish();
  }

  /// Compares day [id] with an earlier one, when no day was given.
  void chooseAfter(String id) {
    _chosenAfter = id;
    _publish();
  }

  void selectPose(PhotoPose pose) {
    _pose = pose;
    _publish();
  }

  void _publish() {
    final entries = _entries;
    final profile = _profile;
    if (entries == null || profile == null) return;
    final later = _afterId == null
        ? comparableDays(entries)
        : const <BodyEntry>[];
    final after = switch (_afterId) {
      final id? => entries.where((entry) => entry.id == id).firstOrNull,
      null =>
        later.where((entry) => entry.id == _chosenAfter).firstOrNull ??
            later.firstOrNull,
    };
    if (after == null) {
      emit(
        MeasurementSummaryState(
          status: _afterId == null
              ? MeasurementSummaryStatus.nothingToCompare
              : MeasurementSummaryStatus.notFound,
          baseline: _baseline,
          pose: _pose,
        ),
      );
      return;
    }
    // A chosen day that is gone gave the newest.
    if (after.id != _chosenAfter) _chosenAfter = null;
    final before = _findBaseline(entries, after, _baseline);
    // A chosen day that is gone gave the previous one.
    if (_baseline case ChosenDay(:final id) when before?.id != id) {
      _baseline = const PreviousDay();
    }
    final summary = MeasurementSummary.of(
      after: after,
      before: before,
      profile: profile,
      now: _clock(),
    );
    final poses = summary.poses;
    final pose = poses.contains(_pose) ? _pose : poses.firstOrNull;
    emit(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: summary,
        baseline: _baseline,
        candidates: baselineCandidates(entries, after),
        laterCandidates: later,
        pose: pose,
        photoFiles: _photoFiles,
      ),
    );
    if (pose != null) {
      unawaited(_restore([?before?.photos[pose], ?after.photos[pose]]));
    }
  }

  /// Those of [paths] that are not known yet, each once at a time.
  Future<void> _restore(List<String> paths) async {
    final uid = _entriesFollower.uid;
    final missing = [
      for (final path in paths)
        if (!_photoFiles.containsKey(path) && _restoring.add(path)) path,
    ];
    if (missing.isEmpty) return;
    final found = await Future.wait(missing.map(_restorePhoto.call));
    _restoring.removeAll(missing);
    if (isClosed || uid != _entriesFollower.uid) return;
    _photoFiles = {
      ..._photoFiles,
      for (final (i, path) in missing.indexed) path: ?found[i],
    };
    if (state.status == MeasurementSummaryStatus.ready) {
      emit(
        MeasurementSummaryState(
          status: state.status,
          summary: state.summary,
          baseline: state.baseline,
          candidates: state.candidates,
          laterCandidates: state.laterCandidates,
          pose: state.pose,
          photoFiles: _photoFiles,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _entriesFollower.cancel();
    await _profileFollower.cancel();
    return super.close();
  }
}
