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

  /// Choosing the later day: there is no measurement day.
  noMeasurementDays,
}

class MeasurementSummaryState extends Equatable {
  const MeasurementSummaryState({
    this.status = MeasurementSummaryStatus.loading,
    this.summary,
    this.baseline = const PreviousDay(),
    this.candidates = const [],
    this.laterCandidates = const [],
    this.photoFiles = const {},
    this.fetching = const {},
  });

  final MeasurementSummaryStatus status;

  /// Set while [status] is ready.
  final MeasurementSummary? summary;

  /// What the entry is compared with.
  final Baseline baseline;

  /// The earlier measurement days it can be compared with, newest first.
  final List<BodyEntry> candidates;

  /// While choosing the later day, the measurement days it can be: those
  /// after the earlier one, newest first.
  final List<BodyEntry> laterCandidates;

  /// The files of the two days' photos on this device, by storage path.
  final Map<String, String> photoFiles;

  /// The photos being fetched from the backup, by storage path.
  final Set<String> fetching;

  @override
  List<Object?> get props => [
    status,
    summary,
    baseline,
    candidates,
    laterCandidates,
    photoFiles,
    fetching,
  ];
}

/// One measurement day of whoever is signed in compared with an earlier
/// one, both followed live with the profile (body fat, target weight):
/// the previous measurement day unless another [Baseline] is chosen. The
/// later day is the entry `afterId`; without one it is the day a link
/// shows ([showDay]; gone: not found) or the user picks ([chooseAfter];
/// gone: the newest), else the newest of [comparableDays], else the only
/// measurement day on its own. The two days' photos are fetched from the
/// backup when not on this device.
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
        emit(MeasurementSummaryState(baseline: _baseline));
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

  /// Photos the backup did not give; not asked for again.
  final _unavailable = <String>{};
  List<BodyEntry>? _entries;
  UserProfile? _profile;
  Baseline _baseline = const PreviousDay();
  String? _chosenAfter;

  /// The day a link asked for; not found once it is gone.
  String? _linkedAfter;
  Map<String, String> _photoFiles = const {};

  void retry() {
    _entriesFollower.resume();
    _profileFollower.resume();
  }

  void chooseBaseline(Baseline baseline) {
    _baseline = baseline;
    _publish();
  }

  /// Compares day [id] with an earlier one, when no day was given; the
  /// newest once it is gone.
  void chooseAfter(String id) {
    _chosenAfter = id;
    _linkedAfter = null;
    _publish();
  }

  /// Shows day [id], as a link asks; not found once it is gone.
  void showDay(String id) {
    _chosenAfter = id;
    _linkedAfter = id;
    _publish();
  }

  void _publish() {
    final entries = _entries;
    final profile = _profile;
    if (entries == null || profile == null) return;
    final days = [
      for (final entry in entries)
        if (isMeasurementDay(entry)) entry,
    ];
    BodyEntry? find(String? id) => id == null
        ? null
        : entries.where((entry) => entry.id == id).firstOrNull;
    final linked = _linkedAfter;
    final BodyEntry? after;
    if (_afterId case final id?) {
      after = find(id);
    } else if (linked != null) {
      after = find(linked);
    } else {
      final later = comparableDays(entries);
      after =
          later.where((entry) => entry.id == _chosenAfter).firstOrNull ??
          later.firstOrNull ??
          days.firstOrNull;
    }
    if (after == null) {
      emit(
        MeasurementSummaryState(
          status: _afterId == null && linked == null
              ? MeasurementSummaryStatus.noMeasurementDays
              : MeasurementSummaryStatus.notFound,
          baseline: _baseline,
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
    emit(
      MeasurementSummaryState(
        status: MeasurementSummaryStatus.ready,
        summary: summary,
        baseline: _baseline,
        candidates: baselineCandidates(entries, after),
        laterCandidates: _afterId != null || before == null
            ? const []
            : [
                for (final day in days)
                  if (day.date.isAfter(before.date)) day,
              ],
        photoFiles: _photoFiles,
        fetching: _fetching(summary),
      ),
    );
    unawaited(_restore([...?before?.photos.values, ...after.photos.values]));
  }

  /// Those of [paths] that are not known yet, each once at a time.
  Future<void> _restore(List<String> paths) async {
    final uid = _entriesFollower.uid;
    final missing = [
      for (final path in paths)
        if (!_photoFiles.containsKey(path) &&
            !_unavailable.contains(path) &&
            _restoring.add(path))
          path,
    ];
    if (missing.isEmpty) return;
    final found = await Future.wait(missing.map(_restorePhoto.call));
    _restoring.removeAll(missing);
    if (isClosed || uid != _entriesFollower.uid) return;
    _photoFiles = {
      ..._photoFiles,
      for (final (i, path) in missing.indexed) path: ?found[i],
    };
    _unavailable.addAll([
      for (final (i, path) in missing.indexed)
        if (found[i] == null) path,
    ]);
    _emitPhotos();
  }

  /// The photos of [summary]'s days not on this device yet that the
  /// backup may still give.
  Set<String> _fetching(MeasurementSummary summary) => {
    for (final path in [
      ...?summary.before?.photos.values,
      ...summary.after.photos.values,
    ])
      if (!_photoFiles.containsKey(path) && !_unavailable.contains(path)) path,
  };

  void _emitPhotos() {
    if (state.status != MeasurementSummaryStatus.ready) return;
    emit(
      MeasurementSummaryState(
        status: state.status,
        summary: state.summary,
        baseline: state.baseline,
        candidates: state.candidates,
        laterCandidates: state.laterCandidates,
        photoFiles: _photoFiles,
        fetching: _fetching(state.summary!),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _entriesFollower.cancel();
    await _profileFollower.cancel();
    return super.close();
  }
}
