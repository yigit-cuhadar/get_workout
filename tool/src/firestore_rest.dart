// Minimal Firestore REST client for the content tools.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'exercise_import.dart';

/// Any failure talking to Firestore. [toString] is safe to print: it never
/// contains the token.
sealed class FirestoreException implements Exception {}

/// Firestore answered with an error status.
class FirestoreApiException implements FirestoreException {
  FirestoreApiException(this.request, this.status, this.body);

  final String request;
  final int status;
  final String body;

  /// The `error.status` of the response, e.g. `FAILED_PRECONDITION`.
  String? get errorStatus {
    try {
      final error = (jsonDecode(body) as Map<String, Object?>)['error'];
      return (error as Map<String, Object?>?)?['status'] as String?;
    } on Object {
      return null;
    }
  }

  /// A document changed, appeared or disappeared since it was read.
  bool get preconditionFailed => const {
    'FAILED_PRECONDITION',
    'ALREADY_EXISTS',
    'NOT_FOUND',
  }.contains(errorStatus);

  @override
  String toString() => 'Firestore API error: $request -> HTTP $status\n$body';
}

/// No usable answer: connection, TLS or timeout.
class FirestoreNetworkException implements FirestoreException {
  FirestoreNetworkException(this.request, this.cause);

  final String request;
  final Object cause;

  @override
  String toString() =>
      'Network error: $request: ${cause.toString().split('\n').first}';
}

/// A commit failed after [written] documents were written by earlier
/// commits. The failed commit itself wrote nothing.
class PartialCommitException implements Exception {
  PartialCommitException(this.written, this.cause);

  final int written;
  final FirestoreException cause;

  @override
  String toString() => '$cause';
}

/// A document as listed: its id, raw REST `fields` and `updateTime`.
typedef FirestoreDocument = ({
  String id,
  Map<String, Object?> fields,
  String updateTime,
});

class FirestoreRest {
  FirestoreRest(
    this.projectId,
    this._token, {
    Uri? baseUri,
    this.timeout = const Duration(seconds: 60),
  }) : _base = baseUri ?? Uri.https('firestore.googleapis.com'),
       _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  final String projectId;
  final String _token;
  final Uri _base;
  final HttpClient _client;

  /// Limit for one request, from connecting to the last byte of the answer.
  final Duration timeout;

  /// `projects/<id>/databases/(default)`, the prefix of document names.
  String get databasePath => 'projects/$projectId/databases/(default)';

  /// Every document of [collection], following `nextPageToken`.
  Future<List<FirestoreDocument>> listDocuments(String collection) async {
    final result = <FirestoreDocument>[];
    String? pageToken;
    do {
      final uri = _base.replace(
        path: '/v1/$databasePath/documents/$collection',
        queryParameters: {'pageSize': '300', 'pageToken': ?pageToken},
      );
      final page = await _send('GET', uri);
      final documents = page['documents'] as List<Object?>? ?? const [];
      for (final document in documents.cast<Map<String, Object?>>()) {
        result.add((
          id: (document['name']! as String).split('/').last,
          fields: document['fields'] as Map<String, Object?>? ?? const {},
          updateTime: document['updateTime']! as String,
        ));
      }
      pageToken = page['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return result;
  }

  /// Applies [writes] atomically in one `documents:commit` call.
  Future<void> commit(List<Map<String, Object?>> writes) async {
    final uri = _base.replace(path: '/v1/$databasePath/documents:commit');
    await _send('POST', uri, {'writes': writes});
  }

  /// Commits [writes] in batches of at most [batchSize], in order.
  Future<void> commitInBatches(
    List<Map<String, Object?>> writes, {
    int batchSize = maxWritesPerCommit,
  }) async {
    var written = 0;
    for (final batch in batches(writes, size: batchSize)) {
      try {
        await commit(batch);
      } on FirestoreException catch (e) {
        throw PartialCommitException(written, e);
      }
      written += batch.length;
    }
  }

  void close() => _client.close(force: true);

  Future<Map<String, Object?>> _send(
    String method,
    Uri uri, [
    Map<String, Object?>? body,
  ]) async {
    final label = '$method ${uri.path}';
    final (int status, String text) response;
    try {
      response = await _exchange(method, uri, body).timeout(timeout);
    } on TimeoutException {
      throw FirestoreNetworkException(label, 'no answer in $timeout');
    } on IOException catch (e) {
      // SocketException, HandshakeException, HttpException, ...
      throw FirestoreNetworkException(label, e);
    }
    final (status, text) = response;
    if (status != HttpStatus.ok) {
      throw FirestoreApiException(label, status, text);
    }
    return jsonDecode(text) as Map<String, Object?>;
  }

  Future<(int, String)> _exchange(
    String method,
    Uri uri,
    Map<String, Object?>? body,
  ) async {
    final request = await _client.openUrl(method, uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $_token')
      // Bills the call to this project; needed for user (gcloud) tokens.
      ..set('x-goog-user-project', projectId);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (response.statusCode, text);
  }
}
