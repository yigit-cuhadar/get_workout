import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../programs/domain/program_usecases.dart';
import '../../strength/domain/strength.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import '../domain/body_usecases.dart';

enum BodyListStatus { loading, ready, failure }

class BodyListState extends Equatable {
  const BodyListState({
    this.status = BodyListStatus.loading,
    this.entries = const [],
    this.photoFiles = const {},
    this.range = StrengthRange.free,
    this.points = const [],
    this.olderLocked = false,
    this.writeRejected = false,
  });

  final BodyListStatus status;

  /// Newest first.
  final List<BodyEntry> entries;

  /// The files of the photos on this device, by storage path. Filled in
  /// shortly after [entries].
  final Map<String, String> photoFiles;

  /// The chart's range: the one chosen, as far as Premium allows.
  final StrengthRange range;

  /// The weights in [range], oldest first.
  final List<WeightPoint> points;

  /// A free user has weights from before [StrengthRange.free]; tell them
  /// they are behind Premium.
  final bool olderLocked;

  /// The server refused a save or delete that already looked done; tell the
  /// user, then call [BodyListCubit.rejectionShown].
  final bool writeRejected;

  BodyEntry? entry(String id) =>
      entries.where((entry) => entry.id == id).firstOrNull;

  BodyListState copyWith({
    Map<String, String>? photoFiles,
    bool? writeRejected,
  }) => BodyListState(
    status: status,
    entries: entries,
    photoFiles: photoFiles ?? this.photoFiles,
    range: range,
    points: points,
    olderLocked: olderLocked,
    writeRejected: writeRejected ?? this.writeRejected,
  );

  @override
  List<Object?> get props => [
    status,
    entries,
    photoFiles,
    range,
    points,
    olderLocked,
    writeRejected,
  ];
}

/// The body entries of whoever is signed in, followed live, with the weight
/// chart. Starts over on every user change. Ranges beyond
/// [StrengthRange.free] show only while the user is known to have Premium;
/// the page asks for Premium before choosing one.
class BodyListCubit extends Cubit<BodyListState> {
  BodyListCubit({
    required WatchAuthUser watchAuthUser,
    required WatchBodyEntries watchEntries,
    required WatchRejectedBodyWrites watchRejectedWrites,
    required WatchPremium watchPremium,
    required this._findPhotos,
    required this._restorePhoto,
    required this._reconcilePhotos,
    required this._deleteEntry,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const BodyListState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchEntries.call,
      onUser: (_) {
        _entries = null;
        _chosen = StrengthRange.free;
        _publish();
      },
      onData: (entries) {
        _entries = entries;
        _publish();
        unawaited(_findFiles(entries));
        if (_follower.uid case final uid?) {
          unawaited(_reconcilePhotos(uid, entries));
        }
      },
      onError: (_) {
        _entries = null;
        emit(const BodyListState(status: BodyListStatus.failure));
      },
      logTag: 'body',
    );
    _premiumSubscription = watchPremium().listen((premium) {
      _premium = premium;
      if (_entries != null) _publish();
    });
    _rejectedSubscription = watchRejectedWrites().listen(
      (_) => emit(state.copyWith(writeRejected: true)),
    );
  }

  final FindBodyPhotos _findPhotos;
  final RestoreBodyPhoto _restorePhoto;
  final ReconcileBodyPhotos _reconcilePhotos;
  final _restoring = <String>{};
  final DeleteBodyEntry _deleteEntry;
  final DateTime Function() _clock;
  late final UserStreamFollower<List<BodyEntry>> _follower;
  late final StreamSubscription<bool?> _premiumSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
  List<BodyEntry>? _entries;
  bool? _premium;
  StrengthRange _chosen = StrengthRange.free;

  void retry() => _follower.resume();

  void rejectionShown() => emit(state.copyWith(writeRejected: false));

  /// Shows [range]; a Premium one only once the user is known to have
  /// Premium, which may be after the paywall closed.
  void selectRange(StrengthRange range) {
    _chosen = range;
    if (_entries != null) _publish();
  }

  /// Fetches those of [paths] that are not on this device from the backup,
  /// e.g. on a new phone; call for the photos a page shows. Those that come
  /// back join [BodyListState.photoFiles].
  Future<void> restore(Iterable<String> paths) async {
    final uid = _follower.uid;
    final missing = [
      for (final path in paths.toSet())
        if (!state.photoFiles.containsKey(path) && _restoring.add(path)) path,
    ];
    if (missing.isEmpty) return;
    final found = await Future.wait(missing.map(_restorePhoto.call));
    _restoring.removeAll(missing);
    if (isClosed || uid != _follower.uid) return;
    emit(
      state.copyWith(
        photoFiles: {
          ...state.photoFiles,
          for (final (i, path) in missing.indexed) path: ?found[i],
        },
      ),
    );
  }

  /// Deletes [entry] and its photos; null when that started, else why not.
  Future<Failure?> delete(BodyEntry entry) async {
    final uid = _follower.uid;
    if (uid == null) return const AuthFailure('signed out');
    return (await _deleteEntry((uid: uid, entry: entry))).failureOrNull;
  }

  void _publish() {
    final entries = _entries;
    if (entries == null) {
      emit(BodyListState(writeRejected: state.writeRejected));
      return;
    }
    final now = _clock();
    final range = _chosen.allowed(_premium);
    emit(
      BodyListState(
        status: BodyListStatus.ready,
        entries: entries,
        photoFiles: state.photoFiles,
        range: range,
        points: weightSeries(entries, range: range, now: now),
        olderLocked:
            _premium == false &&
            hasWeightBefore(entries, range: StrengthRange.free, now: now),
        writeRejected: state.writeRejected,
      ),
    );
  }

  /// Files a [restore] finished meanwhile are kept: it may have stored
  /// them after the look here.
  Future<void> _findFiles(List<BodyEntry> entries) async {
    final paths = [for (final entry in entries) ...entry.photos.values];
    final files = await _findPhotos(paths);
    // A newer snapshot or another user has taken over meanwhile.
    if (isClosed || !identical(entries, _entries)) return;
    emit(
      state.copyWith(
        photoFiles: {
          for (final path in paths)
            path: ?(files[path] ?? state.photoFiles[path]),
        },
      ),
    );
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    await _premiumSubscription.cancel();
    await _rejectedSubscription.cancel();
    return super.close();
  }
}
