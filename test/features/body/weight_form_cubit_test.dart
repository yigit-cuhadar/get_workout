import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/domain/body_validation.dart';
import 'package:get_workout/features/body/presentation/weight_form_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 9, 30);

  late MockAuthRepository auth;
  late StreamController<AuthUser?> users;
  late BodyPhotoWorld world;

  setUp(() {
    auth = MockAuthRepository();
    users = StreamController<AuthUser?>.broadcast();
    world = BodyPhotoWorld();
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
  });

  WeightFormCubit build({
    BodyEntry? initial,
    WeightUnit unit = WeightUnit.kg,
  }) => WeightFormCubit(
    saveEntry: world.save(() => now),
    newEntryId: NewBodyEntryId(world.repository),
    getCurrentUser: GetCurrentUser(auth),
    watchAuthUser: WatchAuthUser(auth),
    unit: unit,
    initial: initial,
    clock: () => now,
  );

  test('logs a new weight now, converted from lb', () async {
    final cubit = build(unit: WeightUnit.lb)..setWeight('176,4');

    await cubit.save();

    expect(cubit.state.status, WeightFormStatus.saved);
    final saved = world.repository.entries['id1']!;
    expect(saved.date, now);
    expect(saved.weightKg, closeTo(176.4 * kgPerLb, 1e-9));
    await cubit.close();
  });

  test('the lowest weight shown in lb is accepted', () async {
    final cubit = build(unit: WeightUnit.lb)..setWeight('66.1');

    await cubit.save();

    expect(cubit.state.status, WeightFormStatus.saved);
    await cubit.close();
  });

  test('a weight is required and must be in range', () async {
    final cubit = build();

    await cubit.save();
    expect(cubit.state.issues, {BodyIssue.weightOutOfRange});

    cubit.setWeight('80');
    expect(cubit.state.issues, isEmpty);
    expect(world.repository.calls, isEmpty);
    await cubit.close();
  });

  test('a retry after a failed save saves the same entry', () async {
    world.repository.startFailure = const NetworkFailure();
    final cubit = build()..setWeight('80');

    await cubit.save();
    expect(cubit.state.status, WeightFormStatus.saveFailed);

    world.repository.startFailure = null;
    await cubit.save();

    expect(world.repository.calls, ['add id1', 'add id1']);
    expect(world.repository.entries.keys, ['id1']);
    await cubit.close();
  });

  test('another day is logged at noon', () async {
    final cubit = build()..setDay(DateTime(2026, 11, 3));

    expect(cubit.state.date, DateTime(2026, 11, 3, 12));
    await cubit.close();
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

    final saved = world.repository.entries['e1']!;
    expect(world.repository.calls, ['update e1']);
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
