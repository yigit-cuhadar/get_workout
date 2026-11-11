import 'package:cloud_firestore/cloud_firestore.dart';

typedef ExerciseDocument = ({String id, Map<String, Object?> data});

/// Raw access to `exercises`, documents of every status. Throws the Firestore
/// SDK's errors. `FirestoreCollection` cannot read from the cache only, and
/// its converter would fail a whole list on one malformed document, hence the
/// direct Firestore access.
class FirestoreExerciseSource {
  const FirestoreExerciseSource(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _exercises =>
      _firestore.collection('exercises');

  /// Everything Firestore's offline cache holds; empty before the first sync.
  Future<List<ExerciseDocument>> cached() => _read(_exercises, Source.cache);

  /// The documents written on the server after [after], or all of them when
  /// [after] is null. They land in the offline cache as well.
  Future<List<ExerciseDocument>> changedSince(Timestamp? after) => _read(
    after == null
        ? _exercises
        : _exercises.where('updatedAt', isGreaterThan: after),
    Source.server,
  );

  /// How many documents the server holds, at the cost of one read.
  Future<int> serverCount() async {
    final snapshot = await _exercises.count().get(
      source: AggregateSource.server,
    );
    return snapshot.count ?? 0;
  }

  static Future<List<ExerciseDocument>> _read(
    Query<Map<String, dynamic>> query,
    Source source,
  ) async {
    final snapshot = await query.get(GetOptions(source: source));
    return [for (final doc in snapshot.docs) (id: doc.id, data: doc.data())];
  }
}
