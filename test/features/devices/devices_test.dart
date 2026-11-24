import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/core/device_details.dart';
import 'package:get_workout/features/devices/data/firestore_device_repository.dart';
import 'package:get_workout/features/devices/data/push_token_source.dart';
import 'package:get_workout/features/devices/domain/device.dart';
import 'package:get_workout/features/devices/domain/device_repository.dart';
import 'package:get_workout/features/devices/domain/devices_usecases.dart';
import 'package:get_workout/features/devices/presentation/device_session.dart';
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements DeviceRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class _Tokens implements PushTokenSource {
  String? token;
  final changed = StreamController<void>.broadcast(sync: true);

  @override
  Future<String?> read() async => token;

  @override
  Stream<void> changes() => changed.stream;
}

class _Details implements DeviceDetailsSource {
  _Details(this.details);

  DeviceDetails details;

  @override
  Future<DeviceDetails> read() async => details;
}

const _iphone = Device(
  installId: '0123456789abcdef0123456789abcdef',
  model: 'iPhone15,2',
  platform: 'ios',
  osVersion: '18.1',
  appVersion: '1.0.0+12',
);

void main() {
  setUpAll(() {
    registerFallbackValue(_iphone);
    registerFallbackValue(DateTime(2026));
  });

  group('RecordDevice', () {
    late MockRepository repository;
    final now = DateTime(2026, 11, 21, 12);

    RecordDevice record() => RecordDevice(repository, () => now);

    void lastRecord(DeviceRecord? record) =>
        when(() => repository.lastRecord()).thenAnswer((_) async => Ok(record));

    setUp(() {
      repository = MockRepository();
      when(() => repository.current())
          .thenAnswer((_) async => const Ok(_iphone));
      when(() => repository.record(any(), any(), any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test('writes on this install\'s first run', () async {
      lastRecord(null);
      expect((await record()('u1')).valueOrNull, isTrue);
      verify(() => repository.record('u1', _iphone, now)).called(1);
    });

    test('skips the same user and device within a day', () async {
      lastRecord(
        DeviceRecord(
          uid: 'u1',
          device: _iphone,
          at: now.subtract(const Duration(hours: 23)),
        ),
      );
      expect((await record()('u1')).valueOrNull, isFalse);
      verifyNever(() => repository.record(any(), any(), any()));
    });

    test('writes after a day, for another user or a changed device', () async {
      final cases = [
        DeviceRecord(
          uid: 'u1',
          device: _iphone,
          at: now.subtract(RecordDevice.refreshAfter),
        ),
        DeviceRecord(uid: 'u2', device: _iphone, at: now),
        DeviceRecord(
          uid: 'u1',
          device: const Device(
            installId: '0123456789abcdef0123456789abcdef',
            model: 'iPhone15,2',
            platform: 'ios',
            osVersion: '18.0',
            appVersion: '1.0.0+12',
          ),
          at: now,
        ),
      ];
      for (final last in cases) {
        lastRecord(last);
        expect((await record()('u1')).valueOrNull, isTrue, reason: '$last');
      }
      verify(() => repository.record('u1', _iphone, now)).called(3);
    });

    test('writes when the last record cannot be read', () async {
      when(() => repository.lastRecord())
          .thenAnswer((_) async => const Err(UnknownFailure()));
      expect((await record()('u1')).valueOrNull, isTrue);
    });

    test('records nothing on another platform', () async {
      when(() => repository.current()).thenAnswer(
        (_) async => const Ok(
          Device(
            installId: '0123456789abcdef0123456789abcdef',
            model: '',
            platform: 'macos',
            osVersion: '',
            appVersion: '',
          ),
        ),
      );
      expect((await record()('u1')).valueOrNull, isFalse);
      verifyNever(() => repository.lastRecord());
    });

    test('passes on a failed write', () async {
      lastRecord(null);
      when(() => repository.record(any(), any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      expect((await record()('u1')).failureOrNull, isA<NetworkFailure>());
    });
  });

  group('FirestoreDeviceRepository', () {
    late Directory directory;
    late FakeFirebaseFirestore firestore;
    late _Details details;
    late _Tokens tokens;

    FirestoreDeviceRepository repository() => FirestoreDeviceRepository(
      firestore,
      details,
      () async => directory,
      tokens,
      random: Random(1),
    );

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('devices');
      firestore = FakeFirebaseFirestore();
      tokens = _Tokens();
      details = _Details(
        DeviceDetails(
          appVersion: '1.0.0+12',
          platform: 'ios',
          osVersion: '18.1',
          deviceModel: 'x' * 150,
          locale: 'en-GB',
        ),
      );
    });

    tearDown(() => directory.delete(recursive: true));

    test('keeps one install id, made once, across instances', () async {
      final first = (await repository().current()).valueOrNull!;
      expect(first.installId, matches(RegExp(r'^[0-9a-f]{32}$')));
      final again = (await FirestoreDeviceRepository(
        firestore,
        details,
        () async => directory,
        tokens,
        random: Random(2),
      ).current()).valueOrNull!;
      expect(again.installId, first.installId);
      expect(first.platform, 'ios');
      expect(
        first.model.length,
        FirestoreDeviceRepository.maxLength,
        reason: 'cut to what the rules allow',
      );
    });

    test('writes the device document and remembers the record', () async {
      final repo = repository();
      final device = (await repo.current()).valueOrNull!;
      expect((await repo.lastRecord()).valueOrNull, isNull);
      final at = DateTime(2026, 11, 21, 12);

      expect((await repo.record('u1', device, at)).isOk, isTrue);

      final doc = await firestore
          .doc('users/u1/devices/${device.installId}')
          .get();
      expect(doc.data(), {
        'model': device.model,
        'platform': 'ios',
        'osVersion': '18.1',
        'appVersion': '1.0.0+12',
        'lastSeenAt': isA<Timestamp>(),
      });
      expect(
        (await repo.lastRecord()).valueOrNull,
        DeviceRecord(uid: 'u1', device: device, at: at),
      );
    });

    test('writes and remembers the push token once there is one', () async {
      tokens.token = 'fcm-token';
      final repo = repository();
      final device = (await repo.current()).valueOrNull!;
      expect(device.pushToken, 'fcm-token');
      final at = DateTime(2026, 11, 24, 9);

      await repo.record('u1', device, at);

      final doc = await firestore
          .doc('users/u1/devices/${device.installId}')
          .get();
      expect(doc.data()!['pushToken'], 'fcm-token');
      expect(
        (await repo.lastRecord()).valueOrNull,
        DeviceRecord(uid: 'u1', device: device, at: at),
      );
    });

    test('drops a token the rules would refuse', () async {
      for (final token in [
        '',
        'x' * (FirestoreDeviceRepository.maxTokenLength + 1),
      ]) {
        tokens.token = token;
        expect((await repository().current()).valueOrNull!.pushToken, isNull);
      }
    });

    test('passes on token changes', () async {
      final changes = <void>[];
      repository().pushTokenChanges().listen(changes.add);
      tokens.changed.add(null);
      await pumpEventQueue();
      expect(changes, hasLength(1));
    });
  });

  group('DeviceSession', () {
    late MockRepository repository;
    late StreamController<AuthUser?> users;
    late StreamController<void> tokenChanges;

    setUp(() {
      repository = MockRepository();
      users = StreamController.broadcast(sync: true);
      tokenChanges = StreamController.broadcast(sync: true);
      final auth = MockAuthRepository();
      when(auth.watchUser).thenAnswer((_) => users.stream);
      when(repository.pushTokenChanges).thenAnswer((_) => tokenChanges.stream);
      when(repository.current).thenAnswer((_) async => const Ok(_iphone));
      when(repository.lastRecord).thenAnswer((_) async => const Ok(null));
      when(() => repository.record(any(), any(), any()))
          .thenAnswer((_) async => const Ok(null));
      addTearDown(
        DeviceSession(
          watchAuthUser: WatchAuthUser(auth),
          recordDevice: RecordDevice(repository, DateTime.now),
          watchPushTokenChanges: WatchPushTokenChanges(repository),
        ).cancel,
      );
    });

    test('records for each user and again on a new push token', () async {
      tokenChanges.add(null);
      await pumpEventQueue();
      verifyNever(() => repository.record(any(), any(), any()));

      users.add(const AuthUser(id: 'u1'));
      await pumpEventQueue();
      tokenChanges.add(null);
      await pumpEventQueue();
      verify(() => repository.record('u1', _iphone, any())).called(2);

      users.add(null);
      await pumpEventQueue();
      tokenChanges.add(null);
      await pumpEventQueue();
      verifyNever(() => repository.record(any(), any(), any()));
    });
  });
}
