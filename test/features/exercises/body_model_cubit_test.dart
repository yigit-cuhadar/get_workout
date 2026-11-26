import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:mocktail/mocktail.dart';

class MockModel3D extends Mock implements Model3D {}

class MockWatchAuthUser extends Mock implements WatchAuthUser {}

class MockWatchProfile extends Mock implements WatchProfile {}

void main() {
  final male = MockModel3D();
  final female = MockModel3D();
  late StreamController<AuthUser?> users;
  late StreamController<UserProfile> profiles;
  late List<Sex> loads;
  late int failuresLeft;

  BodyModelCubit build() {
    final watchAuthUser = MockWatchAuthUser();
    final watchProfile = MockWatchProfile();
    when(watchAuthUser.call).thenAnswer((_) => users.stream);
    when(() => watchProfile(any())).thenAnswer((_) => profiles.stream);
    return BodyModelCubit(
      loadModel: (sex) async {
        loads.add(sex);
        if (failuresLeft > 0) {
          failuresLeft--;
          throw const FormatException('broken glb');
        }
        return sex == Sex.female ? female : male;
      },
      watchAuthUser: watchAuthUser,
      watchProfile: watchProfile,
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    users = StreamController<AuthUser?>();
    profiles = StreamController<UserProfile>();
    loads = [];
    failuresLeft = 0;
  });

  test('loads nothing until asked, then the male model by default', () async {
    final cubit = build();
    await settle();
    expect(loads, isEmpty);
    await cubit.load();
    expect(cubit.state, BodyModelReady(male, Sex.male));
    await cubit.close();
  });

  test('a female user gets the female model', () async {
    final cubit = build();
    users.add(const AuthUser(id: 'u1'));
    profiles.add(const UserProfile(sex: Sex.female));
    await settle();
    await cubit.load();
    expect(cubit.state, BodyModelReady(female, Sex.female));
    expect(loads, [Sex.female]);
    await cubit.close();
  });

  test('a change of sex swaps the model, each loaded once', () async {
    final cubit = build();
    await cubit.load();
    users.add(const AuthUser(id: 'u1'));
    profiles.add(const UserProfile(sex: Sex.female));
    await settle();
    await settle();
    expect(cubit.state, BodyModelReady(female, Sex.female));
    profiles.add(const UserProfile(sex: Sex.male));
    await settle();
    expect(cubit.state, BodyModelReady(male, Sex.male));
    expect(loads, [Sex.male, Sex.female]);
    await cubit.close();
  });

  test('loads once, however often it is asked', () async {
    final cubit = build();
    await Future.wait([cubit.load(), cubit.load()]);
    await cubit.load();
    expect(loads, [Sex.male]);
    await cubit.close();
  });

  test('a failure can be retried', () async {
    failuresLeft = 1;
    final cubit = build();
    await cubit.load();
    expect(cubit.state, const BodyModelFailed());
    await cubit.load();
    expect(cubit.state, BodyModelReady(male, Sex.male));
    await cubit.close();
  });
}
