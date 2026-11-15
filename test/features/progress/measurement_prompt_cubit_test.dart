import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/progress/domain/measurement_prompt.dart';
import 'package:get_workout/features/progress/presentation/measurement_prompt_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class MockPromptStore extends Mock implements MeasurementPromptStore {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  final sunday = CalendarDate(2026, 11, 15);
  final settings = SettingsState(
    UserSettings.defaultsFor(null).copyWith(
      measurementReminder: MeasurementReminderSettings(
        enabled: true,
        everyWeeks: 2,
        from: CalendarDate(2026, 11, 1),
      ),
    ),
    loaded: true,
  );

  late StreamController<AuthUser?> users;
  late MockBodyListCubit bodyList;
  late MockSettingsCubit settingsCubit;
  late MockPromptStore store;

  setUpAll(() => registerFallbackValue(CalendarDate(2026, 1, 1)));

  setUp(() {
    users = StreamController<AuthUser?>.broadcast();
    bodyList = MockBodyListCubit();
    whenListen(
      bodyList,
      const Stream<BodyListState>.empty(),
      initialState: const BodyListState(status: BodyListStatus.ready),
    );
    settingsCubit = MockSettingsCubit();
    whenListen(
      settingsCubit,
      const Stream<SettingsState>.empty(),
      initialState: settings,
    );
    store = MockPromptStore();
    when(() => store.loadDismissed(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => store.saveDismissed(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  tearDown(() => users.close());

  MeasurementPromptCubit build() {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return MeasurementPromptCubit(
      watchAuthUser: WatchAuthUser(auth),
      bodyList: bodyList,
      settings: settingsCubit,
      loadDismissed: LoadDismissedPrompt(store),
      dismiss: DismissPrompt(store),
      clock: () => DateTime(2026, 11, 13, 12),
    );
  }

  test('due once the user\'s dismissed date is known', () async {
    final cubit = build();
    expect(cubit.state, isNull);

    users.add(alice);
    await pumpEventQueue();
    expect(cubit.state, MeasurementPrompt(date: sunday, today: false));
    await cubit.close();
  });

  test('a prompt dismissed for its date stays hidden', () async {
    when(() => store.loadDismissed('u1')).thenAnswer((_) async => Ok(sunday));
    final cubit = build();
    users.add(alice);
    await pumpEventQueue();
    expect(cubit.state, isNull);
    await cubit.close();
  });

  test('dismiss hides it at once and keeps the date', () async {
    final cubit = build();
    users.add(alice);
    await pumpEventQueue();

    await cubit.dismiss();
    expect(cubit.state, isNull);
    verify(() => store.saveDismissed('u1', sunday)).called(1);
    await cubit.close();
  });

  test('nothing until the user\'s settings have loaded', () async {
    whenListen(
      settingsCubit,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState(settings.settings),
    );
    final cubit = build();
    users.add(alice);
    await pumpEventQueue();
    expect(cubit.state, isNull);
    await cubit.close();
  });
}
