/// The stored content of an exercise in the content-file shape (an entry of
/// `content/exercises/*.json`), as Firestore holds it in `exercises/{id}`.
/// Shared by the importer and the admin panel, so both write one shape.
///
/// The id becomes the document id and is not stored. Firestore has no arrays
/// of arrays, so each `equipmentAlternatives` set is stored as
/// `{"items": [...]}`. `incrementKg` is always a double, so clients read one
/// type whether the file says `1` or `2.5`.
Map<String, Object?> exerciseContent(Map<String, Object?> json) {
  final content = Map<String, Object?>.of(json)..remove('id');
  final alternatives = content['equipmentAlternatives'];
  if (alternatives is List) {
    content['equipmentAlternatives'] = [
      for (final set in alternatives) {'items': set},
    ];
  }
  final increment = content['incrementKg'];
  if (increment is num) content['incrementKg'] = increment.toDouble();
  return content;
}

/// The inverse of [exerciseContent] for a stored document's fields (without
/// `updatedAt` and `contentHash`): the content-file shape with [id].
Map<String, Object?> exerciseJson(String id, Map<String, Object?> content) {
  final json = <String, Object?>{'id': id, ...content};
  final alternatives = json['equipmentAlternatives'];
  if (alternatives is List) {
    json['equipmentAlternatives'] = [
      for (final set in alternatives)
        set is Map<Object?, Object?> ? set['items'] : set,
    ];
  }
  return json;
}
