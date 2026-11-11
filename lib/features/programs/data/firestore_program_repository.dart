import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../exercises/domain/vocabulary.dart';
import '../domain/active_program.dart';
import '../domain/calendar_date.dart';
import '../domain/program.dart';
import '../domain/program_repository.dart';

/// Programs live in `users/{uid}/programs/{id}`, the active program in the
/// `activeProgram` map of `users/{uid}`, a document shared with other
/// features. `FirestoreCollection` is not used: its converter fails the
/// whole stream on one bad document, and it offers only whole-document
/// writes.
class FirestoreProgramRepository implements ProgramRepository {
  FirestoreProgramRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final _rejected = StreamController<Failure>.broadcast();

  static const _active = 'activeProgram';

  /// Far above any real value, far below where rounding fails.
  static const _maxWhole = 1e9;

  static const _dayFields = {'name', 'items'};
  static const _itemFields = {
    'exerciseId',
    'sets',
    'repMin',
    'repMax',
    'durationS',
    'restS',
    'targetKg',
    'group',
  };

  @override
  Stream<Failure> get rejectedWrites => _rejected.stream;

  @override
  Stream<List<Program>> watchPrograms(String uid) =>
      _programs(uid)
          .snapshots()
          .map((snap) {
            final programs = [
              for (final doc in snap.docs) ?programFromMap(doc.id, doc.data()),
            ];
            return programs..sort(_byName);
          })
          .transform(_failures());

  @override
  Future<Result<Program>> getProgram(String uid, String id) => guard(() async {
    final doc = await _programs(uid).doc(id).get();
    final data = doc.data();
    final program = data == null ? null : programFromMap(id, data);
    if (program == null) throw NotFoundFailure('program $id');
    return program;
  }, mapper: mapFirebaseError);

  @override
  Future<Result<String>> createProgram(String uid, Program program) =>
      guard(() async {
        final doc = _programs(uid).doc();
        _confirmLater(doc.set(programToMap(program)));
        return doc.id;
      }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> updateProgram(String uid, Program program) =>
      guard(() async {
        final id = program.id;
        if (id == null) throw const NotFoundFailure('program without id');
        _confirmLater(
          _programs(uid).doc(id).update({
            'name': program.name,
            'lengthWeeks': program.lengthWeeks ?? FieldValue.delete(),
            'days': _daysToList(program.days),
            'updatedAt': FieldValue.serverTimestamp(),
          }),
        );
      }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> deleteProgram(
    String uid,
    String id, {
    required bool clearActive,
  }) => guard(() async {
    final batch = _firestore.batch()..delete(_programs(uid).doc(id));
    if (clearActive) {
      batch.set(_user(uid), {
        _active: FieldValue.delete(),
      }, SetOptions(merge: true));
    }
    _confirmLater(batch.commit());
  }, mapper: mapFirebaseError);

  @override
  Stream<ActiveProgram?> watchActiveProgram(String uid) =>
      _user(uid)
          .snapshots()
          .map((snap) => activeFromMap(snap.data()?[_active]))
          .transform(_failures());

  /// Removing the map first, in the same batch, leaves nothing of a
  /// previous active program in it, while the rest of the document stays.
  @override
  Future<Result<void>> startProgram(String uid, ActiveProgram active) =>
      guard(() async {
        final user = _user(uid);
        _confirmLater(
          (_firestore.batch()
                ..set(user, {
                  _active: FieldValue.delete(),
                }, SetOptions(merge: true))
                ..set(user, {
                  _active: activeToMap(active),
                }, SetOptions(merge: true)))
              .commit(),
        );
      }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> updateActiveProgram(String uid, ActiveProgram active) =>
      guard(() async {
        _confirmLater(
          _user(uid)
              .set({_active: activeToMap(active)}, SetOptions(merge: true)),
        );
      }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> stopProgram(String uid) => guard(() async {
    _confirmLater(
      _user(uid).set({_active: FieldValue.delete()}, SetOptions(merge: true)),
    );
  }, mapper: mapFirebaseError);

  /// Firestore applies a write to its cache at once but completes it only
  /// when the server confirms, which never happens offline, so callers do
  /// not wait for that.
  void _confirmLater(Future<void> write) => unawaited(
    write.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final failure =
            mapFirebaseError(error) ?? UnknownFailure('$error', error);
        Log.e('programs', 'write rejected: ${failure.message}', error, stack);
        _rejected.add(failure);
      },
    ),
  );

  static StreamTransformer<T, T> _failures<T>() =>
      StreamTransformer.fromHandlers(
        handleError: (error, stack, sink) {
          final failure =
              mapFirebaseError(error) ?? UnknownFailure('$error', error);
          Log.e('programs', failure.message, error, stack);
          sink.addError(failure, stack);
        },
      );

  CollectionReference<Map<String, dynamic>> _programs(String uid) =>
      _firestore.collection('users/$uid/programs');

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  static int _byName(Program a, Program b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id!.compareTo(b.id!);
  }

  /// A new document. Missing values are left out.
  static Map<String, Object?> programToMap(Program program) => {
    'name': program.name,
    'origin': program.origin.code,
    'sourceId': ?program.sourceId,
    'lengthWeeks': ?program.lengthWeeks,
    'days': _daysToList(program.days),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static List<Map<String, Object?>> _daysToList(List<ProgramDay> days) => [
    for (final day in days)
      {
        ...day.extra,
        'name': day.name,
        'items': [
          for (final item in day.items)
            {
              ...item.extra,
              'exerciseId': item.exerciseId,
              'sets': item.sets,
              'repMin': ?item.repMin,
              'repMax': ?item.repMax,
              'durationS': ?item.durationS,
              'restS': item.restS,
              'targetKg': ?item.targetKg,
              'group': ?item.group,
            },
        ],
      },
  ];

  /// Null, after logging, for a document without a name and a list of
  /// days. Days and items that are not maps, and items without an exercise,
  /// are left out; values of the wrong type read as missing. Unknown fields
  /// of days and items are kept for writing back.
  static Program? programFromMap(String id, Map<String, dynamic> map) {
    final name = map['name'];
    final days = map['days'];
    if (name is! String || days is! List) {
      Log.e('programs', 'skipped unreadable program $id');
      return null;
    }
    final sourceId = map['sourceId'];
    return Program(
      id: id,
      name: name,
      origin: ProgramOrigin.values.byCode(map['origin']) ?? ProgramOrigin.own,
      sourceId: sourceId is String ? sourceId : null,
      lengthWeeks: _whole(map['lengthWeeks']),
      days: daysFromList(days),
    );
  }

  /// The stored `days` of a user's or a catalogue program, read as
  /// [programFromMap] reads them.
  static List<ProgramDay> daysFromList(List<Object?> days) => [
    for (final day in days)
      if (day is Map) _dayFromMap(day),
  ];

  static ProgramDay _dayFromMap(Map<Object?, Object?> map) {
    final name = map['name'];
    final items = map['items'];
    return ProgramDay(
      name: name is String ? name : '',
      items: [
        if (items is List)
          for (final item in items)
            if (item is Map && item['exerciseId'] is String) _itemFromMap(item),
      ],
      extra: _extra(map, _dayFields),
    );
  }

  static ProgramItem _itemFromMap(Map<Object?, Object?> map) {
    final target = map['targetKg'];
    final group = map['group'];
    return ProgramItem(
      exerciseId: map['exerciseId']! as String,
      sets: _whole(map['sets']) ?? 0,
      repMin: _whole(map['repMin']),
      repMax: _whole(map['repMax']),
      durationS: _whole(map['durationS']),
      restS: _whole(map['restS']) ?? 0,
      targetKg: target is num && target.isFinite ? target.toDouble() : null,
      group: group is String && group.isNotEmpty ? group : null,
      extra: _extra(map, _itemFields),
    );
  }

  static Map<String, Object?> _extra(
    Map<Object?, Object?> map,
    Set<String> known,
  ) => {
    for (final MapEntry(:key, :value) in map.entries)
      if (key is String && !known.contains(key)) key: value,
  };

  static int? _whole(Object? value) =>
      value is num && value.abs() <= _maxWhole ? value.round() : null;

  static Map<String, Object?> activeToMap(ActiveProgram active) => {
    'programId': active.programId,
    'weekdays': active.weekdays,
    'nextDayIndex': active.nextDayIndex,
    'nextDate': active.nextDate.toIso(),
    'startedAt': Timestamp.fromDate(active.startedAt),
  };

  /// Null for anything but a map with a program id, at least one weekday
  /// from 1 to 7, a `YYYY-MM-DD` next date and a start time. Weekdays out of
  /// range are dropped and a missing day index reads as the first day.
  static ActiveProgram? activeFromMap(Object? raw) {
    if (raw is! Map) return null;
    final programId = raw['programId'];
    final weekdays = raw['weekdays'];
    final nextDate = CalendarDate.tryParse(raw['nextDate']);
    final startedAt = raw['startedAt'];
    final days = [
      if (weekdays is List)
        for (final day in weekdays)
          if (day is int && day >= 1 && day <= 7) day,
    ];
    if (programId is! String ||
        programId.isEmpty ||
        days.isEmpty ||
        nextDate == null ||
        startedAt is! Timestamp) {
      if (raw.isNotEmpty) Log.e('programs', 'unreadable active program');
      return null;
    }
    final index = _whole(raw['nextDayIndex']);
    return ActiveProgram(
      programId: programId,
      weekdays: days,
      nextDayIndex: index == null || index < 0 ? 0 : index,
      nextDate: nextDate,
      startedAt: startedAt.toDate(),
    );
  }
}
