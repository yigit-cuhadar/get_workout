// Pure parts of tool/import_content.dart: turning content JSON (exercises and
// programs) into Firestore documents, hashing them and deciding what to
// write.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get_workout/features/exercises/data/exercise_content.dart';

export 'package:get_workout/features/exercises/data/exercise_content.dart'
    show exerciseContent;

/// Firestore allows at most 500 writes in one commit.
const maxWritesPerCommit = 500;

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

/// A content document ready to be written.
class ContentDoc {
  ContentDoc(this.path, this.content) : hash = contentHash(content);

  /// `exercises/<id>` for an entry of `content/exercises/*.json`.
  factory ContentDoc.exercise(Map<String, Object?> json) =>
      ContentDoc('exercises/${json['id']}', exerciseContent(json));

  /// The document path below `documents/`, e.g. `exercises/ex_a`.
  final String path;
  final Map<String, Object?> content;
  final String hash;

  /// The stored fields: the content plus its `contentHash`. `updatedAt` is
  /// added by the server through a field transform.
  Map<String, Object?> get fields =>
      encodeFields({...content, 'contentHash': hash});
}

/// A JSON value for a Firestore REST `Value`. Types the content never uses
/// (timestamps, references, ...) come back as `{kind: raw}`, so a document
/// holding one never matches a hash of file content.
Object? decodeValue(Map<String, Object?> value) {
  final MapEntry(key: kind, value: raw) = value.entries.single;
  return switch (kind) {
    'nullValue' => null,
    'booleanValue' || 'stringValue' => raw,
    'integerValue' => int.parse(raw! as String),
    // JSON may carry 1.0 as 1, and NaN or Infinity as strings.
    'doubleValue' when raw is num => raw.toDouble(),
    'doubleValue' => double.parse(raw! as String),
    'arrayValue' => [
      for (final item
          in (raw! as Map<String, Object?>)['values'] as List<Object?>? ??
              const [])
        decodeValue(item! as Map<String, Object?>),
    ],
    'mapValue' => decodeFields(
      (raw! as Map<String, Object?>)['fields'] as Map<String, Object?>? ??
          const {},
    ),
    _ => {kind: raw},
  };
}

/// JSON for Firestore REST `fields`.
Map<String, Object?> decodeFields(Map<String, Object?> fields) => {
  for (final MapEntry(:key, :value) in fields.entries)
    key: decodeValue(value! as Map<String, Object?>),
};

/// The two documents of a `content/programs/<id>.json`: the catalog card
/// `programs/<id>` (every field but `id` and `days`) and its detail
/// `programs/<id>/detail/main` (`days`), each with its own hash, so the card
/// list never loads the days and either can change alone.
({ContentDoc card, ContentDoc detail}) programDocs(Map<String, Object?> json) {
  final path = 'programs/${json['id']}';
  return (
    card: ContentDoc(
      path,
      Map<String, Object?>.of(json)
        ..remove('id')
        ..remove('days'),
    ),
    detail: ContentDoc('$path/detail/main', {'days': json['days']}),
  );
}

/// What the import needs to know about an existing content document.
class RemoteDocument {
  RemoteDocument({
    required this.storedHash,
    required this.actualHash,
    required this.updateTime,
  });

  /// Hashes the decoded [fields] of a document read with [updateTime].
  factory RemoteDocument.fromFields(
    Map<String, Object?> fields,
    String updateTime,
  ) {
    final content = Map<String, Object?>.of(fields)
      ..remove('contentHash')
      ..remove('updatedAt');
    // A whole number written from the web (the admin panel) is stored as an
    // integer; an exercise file's 2 and 2.0 are the same increment.
    final increment = content['incrementKg'];
    if (increment is int) content['incrementKg'] = increment.toDouble();
    final stored = fields['contentHash'];
    return RemoteDocument(
      storedHash: stored is String ? stored : null,
      actualHash: contentHash(content),
      updateTime: updateTime,
    );
  }

  /// The `contentHash` field, written by the last import.
  final String? storedHash;

  /// The hash of what the document holds now.
  final String actualHash;

  /// Used as the write precondition.
  final String updateTime;

  /// Changed since the last import, by the admin panel or by hand: the panel
  /// leaves `contentHash` alone, so it no longer matches.
  bool get editedElsewhere => storedHash != actualHash;
}

/// What an import does, by document path. Each list is sorted, so exercises
/// come before programs and a card before its detail.
class ImportPlan {
  ImportPlan({
    required this.created,
    required this.updated,
    required this.unchanged,
    required this.edited,
    required this.orphaned,
    required this.force,
  });

  final List<String> created;
  final List<String> updated;
  final List<String> unchanged;

  /// Edited outside the import and different from the file. Skipped unless
  /// [force], so an edit made in the admin panel is never lost silently.
  final List<String> edited;

  /// In Firestore but not in the files. Never deleted: content is retired by
  /// setting `status` in its file.
  final List<String> orphaned;

  final bool force;

  List<String> get toWrite =>
      [...created, ...updated, if (force) ...edited]..sort();

  /// Edited documents left as they are; the import then fails.
  List<String> get skipped => force ? const [] : edited;
}

/// Compares the files' hashes ([local]) with what Firestore holds ([remote]).
ImportPlan planImport(
  Map<String, String> local,
  Map<String, RemoteDocument> remote, {
  bool force = false,
}) {
  final created = <String>[], updated = <String>[], unchanged = <String>[];
  final edited = <String>[];
  for (final MapEntry(key: id, value: hash) in local.entries) {
    final existing = remote[id];
    if (existing == null) {
      created.add(id);
    } else if (existing.actualHash == hash) {
      // Same content as the file. Rewrite only to repair a stale hash.
      (existing.editedElsewhere ? updated : unchanged).add(id);
    } else if (existing.editedElsewhere) {
      edited.add(id);
    } else {
      updated.add(id);
    }
  }
  final orphaned = remote.keys.where((id) => !local.containsKey(id)).toList();
  return ImportPlan(
    created: created..sort(),
    updated: updated..sort(),
    unchanged: unchanged..sort(),
    edited: edited..sort(),
    orphaned: orphaned..sort(),
    force: force,
  );
}

/// Splits [items] into chunks of at most [size].
List<List<T>> batches<T>(List<T> items, {int size = maxWritesPerCommit}) => [
  for (var i = 0; i < items.length; i += size)
    items.sublist(i, i + size > items.length ? items.length : i + size),
];

/// A `documents:commit` write that replaces the document at [doc]'s path
/// with it and sets `updatedAt` to the server time. With [updateTime] (from the read) it
/// only succeeds if the document has not changed since; without it, only if
/// the document still does not exist.
Map<String, Object?> contentWrite(
  String databasePath,
  ContentDoc doc, {
  String? updateTime,
}) => {
  'update': {
    'name': '$databasePath/documents/${doc.path}',
    'fields': doc.fields,
  },
  'updateTransforms': [
    {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
  ],
  'currentDocument': updateTime == null
      ? {'exists': false}
      : {'updateTime': updateTime},
};
