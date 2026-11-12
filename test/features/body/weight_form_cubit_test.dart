import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/domain/body_validation.dart';
import 'package:get_workout/features/body/presentation/weight_form_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyRepository extends Mock implements BodyRepository {}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 9, 30);

  late MockAuthRepository auth;
  late MockBodyRepository repository;
  late StreamController<AuthUser?> users;

  setUpAll(() {
    registerFallbackValue(BodyEntry(id: 'x', date: DateTime(2026)));
  });

  setUp(() {
    auth = MockAuthRepository();
    repository = MockBodyRepository();
    users = StreamController<AuthUser?>.broadcast();
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.newEntryId(any())).thenReturn('new');
    when(() => repository.addEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.updateEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  WeightFormCubit build({BodyEntry? initial, WeightUnit unit = WeightUnit.kg}) {
    final store = FakePhotoStore();
    return WeightFormCubit(
      saveEntry: SaveBodyEntry(
        repository,
        store,
        BodyPhotoSync(FakeBackupQueue(), store, FakeBackup()),
        clock: () => now,
      ),
      newEntryId: NewBodyEntryId(repository),
      getCurrentUser: GetCurrentUser(auth),
      watchAuthUser: WatchAuthUser(auth),
      unit: unit,
      initial: initial,
      clock: () => now,
    );
  }

  test('logs a new weight now, converted from lb', () async {
    final cubit = build(unit: WeightUnit.lb)..setWeight('176,4');

    await cubit.save();

    expect(cubit.state.status, WeightFormStatus.saved);
    final saved =
        verify(() => repository.addEntry('u1', captureAny())).captured.single
            as BodyEntry;
    expect(saved.id, 'new');
    expect(saved.date, now);
    expect(saved.weightKg, closeTo(176.4 * kgPerLb, 1e-9));
    await cubit.close();
  });

  test('a weight is required and must be in range', () async {
    final cubit = build();

    await cubit.save();
    expect(cubit.state.issues, {BodyIssue.weightOutOfRange});

    cubit.setWeight('80');
    expect(cubit.state.issues, isEmpty);
    verifyNever(() => repository.addEntry(any(), any()));
    await cubit.close();
  });

  test('another day is logged at noon', () {
    final cubit = build()..setDay(DateTime(2026, 11, 3));

    expect(cubit.state.date, DateTime(2026, 11, 3, 12));
    unawaited(cubit.close());
  });

  test('an unchanged weight keeps its stored value exactly', () async {
    final initial = BodyEntry(
      id: 'e1',
      date: DateTime(2026, 11, 1),
      weightKg: 80.123,
      measurements: const {BodyMeasurement.waist: 85},
    );
    final cubit = build(initial: initial);
    expect(cubit.state.weight, '80.1');

    cubit.setDay(DateTime(2026, 11, 2));
    await cubit.save();

    final saved =
        verify(() => repository.updateEntry('u1', captureAny())).captured.single
            as BodyEntry;
    expect(saved.weightKg, 80.123);
    expect(saved.measurements, initial.measurements);
    await cubit.close();
  });

  test('closes when the user changes', () async {
    final cubit = build();

    users.add(const AuthUser(id: 'u2', isAnonymous: true));
    await pumpEventQueue();

    expect(cubit.state.status, WeightFormStatus.closed);
    await cubit.close();
  });
}
