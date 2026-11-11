import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/firestore_rest.dart';

typedef _Request = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  Object? body,
});

/// A local Firestore stand-in: answers each request with the next of
/// [responses] and records what it got.
class _Stub {
  late final HttpServer server;
  final requests = <_Request>[];
  final responses = <(int, Object)>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        headers: {
          'authorization': request.headers.value('authorization') ?? '',
          'x-goog-user-project':
              request.headers.value('x-goog-user-project') ?? '',
        },
        body: text.isEmpty ? null : jsonDecode(text),
      ));
      final (status, body) = responses.removeAt(0);
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
  }

  FirestoreRest client({Duration timeout = const Duration(seconds: 5)}) =>
      FirestoreRest(
        'demo',
        'fake-test-token',
        baseUri: Uri.http('127.0.0.1:${server.port}'),
        timeout: timeout,
      );
}

Map<String, Object?> _document(String id, Map<String, Object?>? fields) => {
  'name': 'projects/demo/databases/(default)/documents/exercises/$id',
  'fields': ?fields,
  'updateTime': '2026-11-11T10:00:00.$id',
};

/// The error [future] fails with, which must be a [T].
Future<T> _thrown<T extends Object>(Future<Object?> future) async {
  try {
    await future;
  } on T catch (e) {
    return e;
  }
  fail('expected a $T');
}

Map<String, Object?> _error(int code, String status) => {
  'error': {'code': code, 'status': status, 'message': 'stub'},
};

void main() {
  late _Stub stub;
  late FirestoreRest firestore;

  setUp(() async {
    stub = _Stub();
    await stub.start();
    firestore = stub.client();
  });

  tearDown(() async {
    firestore.close();
    await stub.server.close(force: true);
  });

  group('listDocuments', () {
    test('follows nextPageToken and keeps documents without fields', () async {
      stub.responses.addAll([
        (
          200,
          {
            'documents': [
              _document('1', {
                'contentHash': {'stringValue': 'h1'},
              }),
            ],
            'nextPageToken': 'page2',
          },
        ),
        (
          200,
          {
            'documents': [_document('2', null)],
          },
        ),
      ]);

      final documents = await firestore.listDocuments('exercises');

      expect(documents.map((d) => d.id), ['1', '2']);
      expect(documents[0].fields, {
        'contentHash': {'stringValue': 'h1'},
      });
      expect(documents[1].fields, isEmpty);
      expect(documents[1].updateTime, '2026-11-11T10:00:00.2');

      final [first, second] = stub.requests;
      expect(
        first.uri.path,
        '/v1/projects/demo/databases/(default)/documents/exercises',
      );
      expect(first.uri.queryParameters, {'pageSize': '300'});
      expect(second.uri.queryParameters, {
        'pageSize': '300',
        'pageToken': 'page2',
      });
      expect(first.headers, {
        'authorization': 'Bearer fake-test-token',
        'x-goog-user-project': 'demo',
      });
    });

    test('returns nothing for an empty collection', () async {
      stub.responses.add((200, <String, Object?>{}));
      expect(await firestore.listDocuments('exercises'), isEmpty);
    });

    test('throws the status and body on an HTTP error', () async {
      stub.responses.add((403, _error(403, 'PERMISSION_DENIED')));

      final error = await _thrown<FirestoreApiException>(
        firestore.listDocuments('exercises'),
      );

      expect(error.status, 403);
      expect(error.errorStatus, 'PERMISSION_DENIED');
      expect(error.preconditionFailed, isFalse);
      expect('$error', contains('PERMISSION_DENIED'));
      expect('$error', isNot(contains('fake-test-token')));
    });
  });

  group('commitInBatches', () {
    List<Map<String, Object?>> writes(int count) => [
      for (var i = 0; i < count; i++) {'n': i},
    ];

    test('commits in order, at most batchSize writes each', () async {
      stub.responses.addAll([(200, {}), (200, {}), (200, {})]);

      await firestore.commitInBatches(writes(5), batchSize: 2);

      expect(stub.requests.map((r) => r.method), ['POST', 'POST', 'POST']);
      expect(
        stub.requests.first.uri.path,
        '/v1/projects/demo/databases/(default)/documents:commit',
      );
      expect(
        stub.requests.map(
          (r) => ((r.body! as Map)['writes'] as List).map((w) => w['n']),
        ),
        [
          [0, 1],
          [2, 3],
          [4],
        ],
      );
    });

    test(
      'reports a failed precondition and what earlier batches wrote',
      () async {
        stub.responses.addAll([
          (200, {}),
          (400, _error(400, 'FAILED_PRECONDITION')),
        ]);

        final error = await _thrown<PartialCommitException>(
          firestore.commitInBatches(writes(5), batchSize: 2),
        );

        expect(error.written, 2);
        final cause = error.cause as FirestoreApiException;
        expect(cause.status, 400);
        expect(cause.preconditionFailed, isTrue);
        expect(stub.requests, hasLength(2));
      },
    );

    test('wraps HTTP errors of the first batch with nothing written', () async {
      stub.responses.add((500, _error(500, 'INTERNAL')));

      final error = await _thrown<PartialCommitException>(
        firestore.commitInBatches(writes(1)),
      );

      expect(error.written, 0);
      expect((error.cause as FirestoreApiException).preconditionFailed, false);
    });
  });

  group('network errors', () {
    test('a refused connection is a FirestoreNetworkException', () async {
      final port = stub.server.port;
      await stub.server.close(force: true);
      final offline = FirestoreRest(
        'demo',
        'fake-test-token',
        baseUri: Uri.http('127.0.0.1:$port'),
      );
      addTearDown(offline.close);

      await expectLater(
        offline.listDocuments('exercises'),
        throwsA(isA<FirestoreNetworkException>()),
      );
    });

    test('a request with no answer times out', () async {
      final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => silent.close(force: true));
      silent.listen((_) {}); // Never answers.
      final slow = FirestoreRest(
        'demo',
        'fake-test-token',
        baseUri: Uri.http('127.0.0.1:${silent.port}'),
        timeout: const Duration(milliseconds: 200),
      );
      addTearDown(slow.close);

      final error = await _thrown<FirestoreNetworkException>(slow.commit([]));

      expect('$error', contains('no answer'));
    });
  });
}
