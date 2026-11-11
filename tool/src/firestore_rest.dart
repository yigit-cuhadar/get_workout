// Minimal Firestore REST client for the content tools.
import 'dart:convert';
import 'dart:io';

class FirestoreApiException implements Exception {
  FirestoreApiException(this.request, this.status, this.body);

  final String request;
  final int status;
  final String body;

  @override
  String toString() => 'Firestore API error: $request -> HTTP $status\n$body';
}

class FirestoreRest {
  FirestoreRest(this.projectId, this._token);

  final String projectId;
  final String _token;
  final _client = HttpClient();

  /// `projects/<id>/databases/(default)`, the prefix of document names.
  String get databasePath => 'projects/$projectId/databases/(default)';

  /// Every document of [collection] mapped to its [field] string value, or
  /// `null` when the document lacks it. Reads only that field.
  Future<Map<String, String?>> readField(
    String collection,
    String field,
  ) async {
    final result = <String, String?>{};
    String? pageToken;
    do {
      final uri = Uri.https(
        'firestore.googleapis.com',
        '/v1/$databasePath/documents/$collection',
        {'pageSize': '300', 'mask.fieldPaths': field, 'pageToken': ?pageToken},
      );
      final page = await _send('GET', uri);
      final documents = page['documents'] as List<Object?>? ?? const [];
      for (final document in documents.cast<Map<String, Object?>>()) {
        final id = (document['name']! as String).split('/').last;
        final fields = document['fields'] as Map<String, Object?>?;
        final value = fields?[field] as Map<String, Object?>?;
        result[id] = value?['stringValue'] as String?;
      }
      pageToken = page['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return result;
  }

  /// Applies [writes] in one `documents:commit` call.
  Future<void> commit(List<Map<String, Object?>> writes) async {
    final uri = Uri.https(
      'firestore.googleapis.com',
      '/v1/$databasePath/documents:commit',
    );
    await _send('POST', uri, {'writes': writes});
  }

  void close() => _client.close();

  Future<Map<String, Object?>> _send(
    String method,
    Uri uri, [
    Map<String, Object?>? body,
  ]) async {
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
    if (response.statusCode != HttpStatus.ok) {
      throw FirestoreApiException(
        '$method ${uri.path}',
        response.statusCode,
        text,
      );
    }
    return jsonDecode(text) as Map<String, Object?>;
  }
}
