import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../exercises/domain/vocabulary.dart';
import '../domain/catalogue_program.dart';
import '../domain/catalogue_repository.dart';
import '../domain/program.dart';
import 'firestore_program_repository.dart';

/// Reads the whole `programs` collection, every status, and keeps the live
/// cards on device: a few dozen small documents, and no composite index
/// (a status filter plus an `order` sort would need one).
class FirestoreCatalogueRepository implements CatalogueRepository {
  FirestoreCatalogueRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<CatalogueProgram>> watchPrograms() => _firestore
      .collection('programs')
      .snapshots()
      .transform(
        StreamTransformer.fromHandlers(
          handleData: (snap, sink) {
            // Offline, a query never loaded before answers from the empty
            // cache.
            if (snap.docs.isEmpty && snap.metadata.isFromCache) {
              sink.addError(const NetworkFailure('catalogue not cached'));
              return;
            }
            sink.add(
              liveProgramsFrom({
                for (final doc in snap.docs) doc.id: doc.data(),
              }),
            );
          },
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('catalogue', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );

  @override
  Future<Result<List<ProgramDay>>> getDays(String id) => guard(() async {
    final doc = await _firestore.doc('programs/$id/detail/main').get();
    final days = doc.data()?['days'];
    if (days is! List || days.isEmpty) throw NotFoundFailure('days of $id');
    return FirestoreProgramRepository.daysFromList(days);
  }, mapper: mapFirebaseError);

  /// The live cards of [docs] (by id) by `order`, then id.
  static List<CatalogueProgram> liveProgramsFrom(
    Map<String, Map<String, dynamic>> docs,
  ) =>
      [
        for (final MapEntry(key: id, value: data) in docs.entries)
          if (data['status'] == ExerciseStatus.live.code)
            ?catalogueProgramFromMap(id, data),
      ]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });

  /// Null, after logging, for a card missing a field the catalogue shows.
  /// Like the rules, only an absent or exactly false `premium` is free.
  static CatalogueProgram? catalogueProgramFromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final level = Level.values.byCode(map['level']);
    final goal = Goal.values.byCode(map['goal']);
    final profile = EquipmentProfile.values.byCode(map['equipmentProfile']);
    final days = map['daysPerWeek'];
    final order = map['order'];
    final weeks = map['lengthWeeks'];
    final equipment = map['equipment'];
    final l10n = {
      if (map['l10n'] case final Map<Object?, Object?> l10n)
        for (final MapEntry(:key, :value) in l10n.entries)
          if (key is String) key: ?_text(value),
    };
    if (level == null ||
        goal == null ||
        profile == null ||
        days is! int ||
        order is! int ||
        !l10n.containsKey(CatalogueProgram.fallbackLanguage)) {
      Log.e('catalogue', 'skipped unreadable program $id');
      return null;
    }
    return CatalogueProgram(
      id: id,
      premium: map.containsKey('premium') && map['premium'] != false,
      level: level,
      goal: goal,
      daysPerWeek: days,
      lengthWeeks: weeks is int ? weeks : null,
      equipment: [
        if (equipment is List)
          for (final code in equipment) ?Equipment.values.byCode(code),
      ],
      equipmentProfile: profile,
      order: order,
      l10n: l10n,
    );
  }

  static CatalogueText? _text(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final summary = value['summary'];
    if (name is! String || name.isEmpty) return null;
    return CatalogueText(name: name, summary: summary is String ? summary : '');
  }
}
