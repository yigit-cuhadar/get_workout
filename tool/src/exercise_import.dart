// Pure parts of tool/import_content.dart: turning content JSON into Firestore
// documents, hashing them and deciding what to write.
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Firestore allows at most 500 writes in one commit.
const maxWritesPerCommit = 500;

/// The stored content of an exercise read from content/exercises/*.json.
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

/// JSON with map keys sorted at every level, so equal content always gives
/// the same string.
String canonicalJson(Object? value) => jsonEncode(_sortKeys(value));

Object? _sortKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sortKeys(value[key])};
  }
  if (value is List) return [for (final item in value) _sortKeys(item)];
  return value;
}

/// SHA-256 of the canonical JSON of [content], as hex.
String contentHash(Map<String, Object?> content) =>
    sha256.convert(utf8.encode(canonicalJson(content))).toString();

/// A Firestore REST `Value` for a JSON value.
Map<String, Object?> encodeValue(Object? value, {bool inArray = false}) {
  return switch (value) {
    null => {'nullValue': null},
    bool() => {'booleanValue': value},
    int() => {'integerValue': '$value'},
    double() => {'doubleValue': value},
    String() => {'stringValue': value},
    List() when inArray => throw ArgumentError.value(
      value,
      'value',
      'Firestore does not allow arrays directly inside arrays',
    ),
    List() => {
      'arrayValue': {
        if (value.isNotEmpty)
          'values': [
            for (final item in value) encodeValue(item, inArray: true),
          ],
      },
    },
    Map() => {
      'mapValue': {if (value.isNotEmpty) 'fields': encodeFields(value.cast())},
    },
    _ => throw ArgumentError.value(value, 'value', 'not a JSON value'),
  };
}

/// Firestore REST `fields` for a map.
Map<String, Object?> encodeFields(Map<String, Object?> map) => {
  for (final entry in map.entries) entry.key: encodeValue(entry.value),
};

/// An exercise ready to be written.
class ExerciseDoc {
  ExerciseDoc(this.id, this.content) : hash = contentHash(content);

  factory ExerciseDoc.fromJson(Map<String, Object?> json) =>
      ExerciseDoc(json['id']! as String, exerciseContent(json));

  final String id;
  final Map<String, Object?> content;
  final String hash;

  /// The stored fields: the content plus its `contentHash`. `updatedAt` is
  /// added by the server through a field transform.
  Map<String, Object?> get fields =>
      encodeFields({...content, 'contentHash': hash});
}

/// What an import does, by exercise id. Each list is sorted.
class ImportPlan {
  ImportPlan({
    required this.created,
    required this.updated,
    required this.unchanged,
    required this.orphaned,
  });

  final List<String> created;
  final List<String> updated;
  final List<String> unchanged;

  /// In Firestore but not in the files. Never deleted: an exercise is retired
  /// by setting `status` in its file.
  final List<String> orphaned;

  List<String> get toWrite => [...created, ...updated]..sort();
}

/// Compares local hashes with the remote ones (`null` when a document has no
/// `contentHash`, which counts as changed).
ImportPlan planImport(Map<String, String> local, Map<String, String?> remote) {
  final created = <String>[], updated = <String>[], unchanged = <String>[];
  for (final MapEntry(key: id, value: hash) in local.entries) {
    if (!remote.containsKey(id)) {
      created.add(id);
    } else if (remote[id] == hash) {
      unchanged.add(id);
    } else {
      updated.add(id);
    }
  }
  final orphaned = remote.keys.where((id) => !local.containsKey(id)).toList();
  return ImportPlan(
    created: created..sort(),
    updated: updated..sort(),
    unchanged: unchanged..sort(),
    orphaned: orphaned..sort(),
  );
}

/// Splits [items] into chunks of at most [size].
List<List<T>> batches<T>(List<T> items, {int size = maxWritesPerCommit}) => [
  for (var i = 0; i < items.length; i += size)
    items.sublist(i, i + size > items.length ? items.length : i + size),
];

/// A `documents:commit` write that replaces `exercises/<id>` with [doc] and
/// sets `updatedAt` to the server time.
Map<String, Object?> exerciseWrite(String databasePath, ExerciseDoc doc) => {
  'update': {
    'name': '$databasePath/documents/exercises/${doc.id}',
    'fields': doc.fields,
  },
  'updateTransforms': [
    {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
  ],
};
