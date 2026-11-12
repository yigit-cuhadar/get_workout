import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/account/data/firestore_consent_repository.dart';
import 'package:get_workout/features/settings/data/firestore_settings_repository.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreConsentRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreConsentRepository(firestore);
  });

  test('not answered without a user document or a boolean', () async {
    expect((await repository.watchConsent('u1').first).consent, isNull);
    await firestore.collection('users').doc('u1').set({
      'settings': {'analyticsConsent': 'yes'},
    });
    expect((await repository.watchConsent('u1').first).consent, isNull);
  });

  test('saves into settings without touching the rest', () async {
    await firestore.collection('users').doc('u1').set({
      'profile': {'goal': 'get_stronger'},
      'settings': {'weightUnit': 'lb'},
    });

    expect((await repository.saveConsent('u1', true)).isOk, isTrue);

    final doc = await firestore.collection('users').doc('u1').get();
    expect(doc.data(), {
      'profile': {'goal': 'get_stronger'},
      'settings': {'weightUnit': 'lb', 'analyticsConsent': true},
    });
    expect((await repository.watchConsent('u1').first).consent, isTrue);
  });

  test('follows changes', () async {
    final answers = expectLater(
      repository.watchConsent('u1').map((stored) => stored.consent),
      emitsInOrder([null, true, false]),
    );
    await pumpEventQueue();
    await repository.saveConsent('u1', true);
    await pumpEventQueue();
    await repository.saveConsent('u1', false);
    await answers;
  });

  test('a user only reads their own', () async {
    await repository.saveConsent('u2', true);
    expect((await repository.watchConsent('u1').first).consent, isNull);
  });

  test('saving the other settings keeps the answer', () async {
    const settings = UserSettings(
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.cm,
    );
    await repository.saveConsent('u1', true);
    await FirestoreSettingsRepository(
      firestore,
      defaults: settings,
    ).saveSettings('u1', settings.copyWith(weightUnit: WeightUnit.lb));
    expect((await repository.watchConsent('u1').first).consent, isTrue);
  });
}
