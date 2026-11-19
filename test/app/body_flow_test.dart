import 'package:bloc_test/bloc_test.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/measurement_summary.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/presentation/body_chart_cubit.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/body/presentation/body_page.dart';
import 'package:get_workout/features/body/presentation/measurement_day_cubit.dart';
import 'package:get_workout/features/body/presentation/measurement_summary_cubit.dart';
import 'package:get_workout/features/body/presentation/measurement_summary_page.dart';
import 'package:get_workout/features/body/presentation/weight_form_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/progress/domain/measurement_prompt.dart';
import 'package:get_workout/features/progress/presentation/measurement_prompt_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import '../features/body/body_fakes.dart';
import '../features/body/fake_camera.dart';
import '../features/programs/fixtures.dart' show FixedPremium;
import 'training_world.dart';

/// Entries in memory whose stream follows every write.
class _LiveBodyRepository extends FakeBodyRepository {
  final _live = LiveData();

  @override
  Stream<List<BodyEntry>> watchEntries(String uid) => _live.watch(
    () => entries.values.toList()..sort((a, b) => b.date.compareTo(a.date)),
  );

  @override
  Future<Result<Confirmation>> addEntry(String uid, BodyEntry entry) async {
    final result = await super.addEntry(uid, entry);
    _live.changed();
    return result;
  }
}

class _StrengthStandIn extends MockCubit<ProgressStrengthState>
    implements ProgressStrengthCubit {}

class _PromptStandIn extends MockCubit<MeasurementPrompt?>
    implements MeasurementPromptCubit {}

class _CardioStandIn extends MockCubit<CardioListState>
    implements CardioListCubit {}

class _ChartStandIn extends MockCubit<BodyChartState>
    implements BodyChartCubit {}

void main() {
  setUp(() {
    CameraPlatform.instance = FakeCameraPlatform([backCamera, frontCamera]);
  });

  /// The body feature over in-memory entries and photos; the Progress
  /// tab's strength, cardio and measurement prompt and the Body page's
  /// chart are stand-ins.
  TrainingWorld world(_LiveBodyRepository entries) => TrainingWorld(
    exercises: const [],
    profile: UserProfile(
      onboardingCompletedAt: DateTime(2026),
      sex: Sex.male,
      weightKg: 81.5,
    ),
  );

  void registerBody(TrainingWorld world, _LiveBodyRepository entries) {
    final store = FakePhotoStore();
    final sync = BodyPhotoSync(FakeBackupQueue(), store, FakeBackup(), entries);
    final syncWeight = syncProfileWeight(entries, world.profiles);
    final save = SaveBodyEntry(
      entries,
      store,
      sync,
      syncWeight,
      clock: () => world.now,
    );
    final list = BodyListCubit(
      watchAuthUser: world.watchUser,
      watchEntries: WatchBodyEntries(entries),
      watchRejectedWrites: WatchRejectedBodyWrites(entries),
      watchPremium: const WatchPremium(FixedPremium(false)),
      watchProfile: WatchProfile(world.profiles),
      findPhotos: FindBodyPhotos(store),
      restorePhoto: RestoreBodyPhoto(sync),
      reconcilePhotos: ReconcileBodyPhotos(sync),
      deleteEntry: DeleteBodyEntry(entries, store, sync, syncWeight),
    );
    world.own(list);
    final cardio = _CardioStandIn();
    when(() => cardio.state)
        .thenReturn(const CardioListState(status: CardioListStatus.ready));
    when(() => cardio.firstWeekday).thenReturn(DateTime.monday);
    sl
      ..registerSingleton<BodyListCubit>(list)
      ..registerSingleton<CardioListCubit>(cardio)
      ..registerFactory(
        () => ProgressBodyCubit(
          bodyList: list,
          watchPremium: const WatchPremium(FixedPremium(false)),
        ),
      )
      ..registerFactory<ProgressStrengthCubit>(() {
        final cubit = _StrengthStandIn();
        when(() => cubit.state).thenReturn(
          const ProgressStrengthState(status: ProgressStrengthStatus.ready),
        );
        return cubit;
      })
      ..registerFactory<MeasurementPromptCubit>(() {
        final cubit = _PromptStandIn();
        when(() => cubit.state).thenReturn(null);
        return cubit;
      })
      ..registerFactoryParam<BodyChartCubit, int, void>((_, _) {
        final cubit = _ChartStandIn();
        when(() => cubit.state)
            .thenReturn(BodyChartState(from: world.now, to: world.now));
        return cubit;
      })
      ..registerFactoryParam<WeightFormCubit, WeightFormSetup, WeightUnit>(
        (setup, unit) => WeightFormCubit(
          setup: setup,
          saveEntry: save,
          newEntryId: NewBodyEntryId(entries),
          getCurrentUser: world.currentUser,
          watchAuthUser: world.watchUser,
          unit: unit,
          clock: () => world.now,
        ),
      )
      ..registerFactoryParam<MeasurementDayCubit, MeasurementDaySetup, void>(
        (setup, _) => MeasurementDayCubit(
          setup: setup,
          saveEntry: save,
          newEntryId: NewBodyEntryId(entries),
          discardCapture: DiscardCapture(store),
          watchEntries: WatchBodyEntries(entries),
          restorePhoto: RestoreBodyPhoto(sync),
          getCurrentUser: world.currentUser,
          watchAuthUser: world.watchUser,
          clock: () => world.now,
        ),
      )
      ..registerFactoryParam<MeasurementSummaryCubit, String?, void>(
        (id, _) => MeasurementSummaryCubit(
          afterId: id,
          watchAuthUser: world.watchUser,
          watchEntries: WatchBodyEntries(entries),
          watchProfile: WatchProfile(world.profiles),
          findBaseline: const FindBaseline(),
          restorePhoto: RestoreBodyPhoto(sync),
        ),
      );
  }

  Future<TrainingWorld> start(
    WidgetTester tester,
    _LiveBodyRepository entries,
  ) async {
    final app = world(entries);
    await app.start(
      tester,
      registerMore: (world) => registerBody(world, entries),
    );
    await openTab(tester, 'Progress');
    return app;
  }

  testWidgets('a weight logged from Progress shows there and on Body', (
    tester,
  ) async {
    final entries = _LiveBodyRepository();
    final app = await start(tester, entries);
    expect(find.text('No weigh-ins yet'), findsOneWidget);

    await tapText(tester, 'Log weight');
    // The ruler starts at the profile weight.
    await tapOn(tester, find.widgetWithText(ForgeButton, 'Save'));

    final entry = entries.entries.values.single;
    expect(entry.weightKg, 81.5);
    expect(entry.date, flowStart);
    expect(find.text('No weigh-ins yet'), findsNothing);
    expect(find.textContaining('81.5'), findsWidgets);

    await tapText(tester, 'Body');
    expect(find.byType(BodyPage), findsOneWidget);
    expect(find.textContaining('81.5'), findsWidgets);

    await app.stop(tester);
  });

  testWidgets('a measurement day steps through to its summary', (tester) async {
    // The test font draws every glyph a full em wide, which overflows the
    // number boxes' "Left" and "Right"; real fonts fit.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) {
        onError!(details);
      }
    };
    addTearDown(() => FlutterError.onError = onError);
    final entries = _LiveBodyRepository();
    final app = await start(tester, entries);

    await tapText(tester, 'Measurement day');
    expect(find.text('Step 1 of 3 · Weight'), findsOneWidget);
    await tapText(tester, 'Next · measurements');
    expect(find.text('Step 2 of 3 · Measurements'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(ListRow, 'Waist'),
        matching: find.byType(TextField),
      ),
      '88',
    );
    await tapText(tester, 'Next · photos');
    expect(find.text('Step 3 of 3 · Photos'), findsOneWidget);
    await tapOn(tester, find.widgetWithText(ForgeButton, 'Save'));

    final entry = entries.entries.values.single;
    expect(entry.weightKg, 81.5);
    expect(entry.measurements, {BodyMeasurement.waist: 88});
    expect(find.byType(MeasurementSummaryPage), findsOneWidget);
    expect(app.front, '/progress/body/summary/${entry.id}');

    await app.stop(tester);
  });
}
