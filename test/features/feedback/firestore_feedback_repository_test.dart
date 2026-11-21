import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/device_details.dart';
import 'package:get_workout/features/feedback/data/firestore_feedback_repository.dart';
import 'package:get_workout/features/feedback/domain/feedback.dart';

class _Device implements DeviceDetailsSource {
  _Device(this._read);
  final Future<DeviceDetails> Function() _read;

  @override
  Future<DeviceDetails> read() => _read();
}

void main() {
  const iphone = DeviceDetails(
    appVersion: '1.0.0+1',
    platform: 'ios',
    osVersion: '26.1',
    deviceModel: 'iPhone17,1',
    locale: 'en-GB',
  );
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<List<Map<String, dynamic>>> stored(String uid) async => [
    for (final doc
        in (await firestore.collection('users/$uid/feedback').get()).docs)
      doc.data(),
  ];

  test('stores an open message under the user, with the device', () async {
    final repository = FirestoreFeedbackRepository(
      firestore,
      _Device(() async => iphone),
    );

    final result = await repository.send(
      'u1',
      const FeedbackDraft(
        source: FeedbackSource.rating,
        message: 'More charts',
        email: 'a@b.co',
      ),
    );

    expect(result.isOk, isTrue);
    final [doc] = await stored('u1');
    expect(doc..remove('createdAt'), {
      'uid': 'u1',
      'email': 'a@b.co',
      'message': 'More charts',
      'source': 'rating',
      'appVersion': '1.0.0+1',
      'platform': 'ios',
      'osVersion': '26.1',
      'deviceModel': 'iPhone17,1',
      'locale': 'en-GB',
      'status': 'open',
    });
  });

  test('the map leaves out an empty email and asks for the server time', () {
    final map = FirestoreFeedbackRepository.toMap(
      'u1',
      const FeedbackDraft(source: FeedbackSource.profile, message: 'Hi'),
      DeviceDetails(deviceModel: 'x' * 150),
    );

    expect(map.containsKey('email'), isFalse);
    expect(map['createdAt'], FieldValue.serverTimestamp());
    expect(
      map['deviceModel'],
      hasLength(FirestoreFeedbackRepository.maxDetail),
    );
  });

  test('sends without the device when it cannot be read', () async {
    final repository = FirestoreFeedbackRepository(
      firestore,
      _Device(() async => throw StateError('no plugin')),
    );

    final result = await repository.send(
      'u1',
      const FeedbackDraft(source: FeedbackSource.profile, message: 'Hi'),
    );

    expect(result.isOk, isTrue);
    final [doc] = await stored('u1');
    expect(doc['message'], 'Hi');
    expect(doc['deviceModel'], '');
  });
}
