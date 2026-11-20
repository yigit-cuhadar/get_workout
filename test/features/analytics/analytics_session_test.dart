import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/analytics/presentation/analytics_session.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../fake_analytics.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProfileCubit extends MockCubit<ProfileState>
    implements ProfileCubit {}

class MockEntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

void main() {
  late StreamController<AuthUser?> users;
  late StreamController<ProfileState> profiles;
  late StreamController<EntitlementState> entitlements;
  late StreamController<ProgramListState> programLists;
  late RecordingTelemetry telemetry;
  late AnalyticsSession session;

  const guest = AuthUser(id: 'g1', isAnonymous: true);

  setUp(() {
    users = StreamController();
    profiles = StreamController();
    entitlements = StreamController();
    programLists = StreamController();
    telemetry = RecordingTelemetry();
    final auth = MockAuthRepository();
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    final profile = MockProfileCubit();
    when(() => profile.state).thenReturn(const ProfileState());
    when(() => profile.stream).thenAnswer((_) => profiles.stream);
    final entitlement = MockEntitlementCubit();
    when(() => entitlement.state).thenReturn(const EntitlementUnknown());
    when(() => entitlement.stream).thenAnswer((_) => entitlements.stream);
    final programs = MockProgramListCubit();
    when(() => programs.state).thenReturn(const ProgramListState());
    when(() => programs.stream).thenAnswer((_) => programLists.stream);
    session = AnalyticsSession(
      watchAuthUser: WatchAuthUser(auth),
      profile: profile,
      entitlement: entitlement,
      programs: programs,
      analytics: fakeAnalytics(telemetry),
    );
  });

  tearDown(() => session.cancel());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('accounts', () {
    test('the user at start is no sign-up or login', () async {
      users.add(const AuthUser(id: 'u1', signInMethods: {SignInMethod.google}));
      await settle();
      expect(telemetry.logged, isEmpty);
      expect(telemetry.properties['account'], 'google');
    });

    test('a guest linking an account signs up with its method', () async {
      users
        ..add(guest)
        ..add(const AuthUser(id: 'g1', signInMethods: {SignInMethod.email}));
      await settle();
      expect(telemetry.logged, [
        [
          'sign_up',
          {'method': 'email'},
        ],
      ]);
      expect(telemetry.properties['account'], 'email');
    });

    test('another account signed in to is a login', () async {
      users
        ..add(guest)
        ..add(const AuthUser(id: 'u2', signInMethods: {SignInMethod.apple}));
      await settle();
      expect(telemetry.logged, [
        [
          'login',
          {'method': 'apple'},
        ],
      ]);
    });

    test('signing out to a new guest is neither', () async {
      users
        ..add(const AuthUser(id: 'u1', signInMethods: {SignInMethod.apple}))
        ..add(null)
        ..add(guest);
      await settle();
      expect(telemetry.logged, isEmpty);
      expect(telemetry.properties['account'], 'guest');
    });
  });

  test('the profile sets level, goal and days when they change', () async {
    profiles.add(
      const ProfileState(
        uid: 'u1',
        status: ProfileStatus.loaded,
        profile: UserProfile(
          goal: Goal.buildMuscle,
          level: Level.beginner,
          daysPerWeek: 3,
        ),
      ),
    );
    await settle();
    expect(telemetry.properties, {
      'level': 'beginner',
      'goal': 'build_muscle',
      'days_per_week': '3',
    });
    telemetry.properties.clear();
    profiles.add(
      const ProfileState(
        uid: 'u1',
        status: ProfileStatus.loaded,
        profile: UserProfile(
          goal: Goal.buildMuscle,
          level: Level.beginner,
          daysPerWeek: 4,
        ),
      ),
    );
    await settle();
    expect(telemetry.properties, {'days_per_week': '4'});
  });

  test('premium follows the entitlement, a trial told apart', () async {
    Future<String?> after(EntitlementState state) async {
      entitlements.add(state);
      await settle();
      return telemetry.properties['premium'];
    }

    expect(await after(const EntitlementInactive()), 'free');
    expect(
      await after(
        const EntitlementActive(Entitlement(isActive: true, isInTrial: true)),
      ),
      'trial',
    );
    // Unknown while switching users leaves it.
    expect(await after(const EntitlementUnknown()), 'trial');
    expect(
      await after(const EntitlementActive(Entitlement(isActive: true))),
      'premium',
    );
  });

  test('has_program follows the active program once the list is '
      'ready', () async {
    final active = ActiveProgram(
      programId: 'p1',
      schedule: const {1: 0},
      nextDayIndex: 0,
      nextDate: CalendarDate(2026, 11, 23),
      startedAt: DateTime(2026, 11, 20),
    );
    programLists.add(ProgramListState(active: active));
    await settle();
    expect(telemetry.properties, isEmpty);
    programLists.add(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: const [Program(id: 'p1', name: 'Push', days: [])],
        active: active,
      ),
    );
    await settle();
    expect(telemetry.properties['has_program'], 'true');
  });
}
