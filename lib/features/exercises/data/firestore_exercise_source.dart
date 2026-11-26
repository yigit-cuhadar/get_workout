import 'package:cloud_firestore/cloud_firestore.dart';

typedef ExerciseDocument = ({String id, Map<String, Object?> data});

/// Raw access to `exercises`, documents of every status, and to the
/// animations: `exercises/{id}/animation/main` and `animationKits/main`, or
/// their `draft` documents, which hold the recipes under review and every kit.
/// Throws the Firestore SDK's errors. `FirestoreCollection` cannot read from the cache only, and
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

  /// The animation document of exercise [id], null when there is none.
  /// From [Source.cache] it throws when the document was never loaded.
  Future<Map<String, dynamic>?> animation(
    String id,
    Source source, {
    bool draft = false,
  }) => _readDocument(
    _exercises.doc(id).collection('animation').doc(_name(draft)),
    source,
  );

  /// The gear kits shared by every animation, null when there are none.
  /// From [Source.cache] it throws when the document was never loaded.
  Future<Map<String, dynamic>?> animationKits(
    Source source, {
    bool draft = false,
  }) => _readDocument(_firestore.doc('animationKits/${_name(draft)}'), source);

  static String _name(bool draft) => draft ? 'draft' : 'main';

  static Future<Map<String, dynamic>?> _readDocument(
    DocumentReference<Map<String, dynamic>> doc,
    Source source,
  ) async => (await doc.get(GetOptions(source: source))).data();

  static Future<List<ExerciseDocument>> _read(
    Query<Map<String, dynamic>> query,
    Source source,
  ) async {
    final snapshot = await query.get(GetOptions(source: source));
    return [for (final doc in snapshot.docs) (id: doc.id, data: doc.data())];
  }
}
