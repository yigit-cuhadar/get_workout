import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/unsaved_changes.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/body/presentation/measurement_day_cubit.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/body/presentation/measurement_day_page.dart';
import 'package:get_workout/features/body/presentation/widgets/pose_camera.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'fake_camera.dart';

class _MeasurementDayCubit extends MockCubit<MeasurementDayState>
    implements MeasurementDayCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _ProfileCubit extends MockCubit<ProfileState> implements ProfileCubit {}

class _BodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

void main() {
  late _MeasurementDayCubit cubit;

  const groups = [
    [BodyMeasurement.waist],
    [BodyMeasurement.leftUpperArm, BodyMeasurement.rightUpperArm],
  ];
  const start = MeasurementDayState(weight: 82.9, groups: groups);
  final year = DateTime.now().year;

  setUp(() {
    CameraPlatform.instance = FakeCameraPlatform([backCamera, frontCamera]);
    cubit = _MeasurementDayCubit();
    when(() => cubit.hasChanges).thenReturn(false);
    when(() => cubit.next()).thenAnswer((_) async {});
    when(() => cubit.back()).thenReturn(true);
    final list = _BodyListCubit();
    when(() => list.state).thenReturn(
      BodyListState(
        status: BodyListStatus.ready,
        entries: [
          BodyEntry(id: 'a', date: DateTime(year, 10, 29, 8), weightKg: 83.2),
        ],
      ),
    );
    sl.registerSingleton<BodyListCubit>(list);
    sl.registerFactoryParam<MeasurementDayCubit, MeasurementDaySetup, void>(
      (_, _) => cubit,
    );
  });

  tearDown(sl.reset);

  Future<void> show(
    WidgetTester tester,
    MeasurementDayState state, {
    Stream<MeasurementDayState>? states,
  }) async {
    if (states == null) {
      when(() => cubit.state).thenReturn(state);
    } else {
      whenListen(cubit, states, initialState: state);
    }
    // A phone's width, tall enough for every tile.
    tester.view
      ..physicalSize = const Size(390 * 3, 1600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The test font draws every glyph a full em wide, which overflows the
    // number boxes' "Left" and "Right"; real fonts fit.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) {
        onError!(details);
      }
    };
    addTearDown(() => FlutterError.onError = onError);
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final profile = _ProfileCubit();
    when(() => profile.state).thenReturn(const ProfileState());
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: UnsavedChanges(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsCubit>.value(value: settings),
            BlocProvider<ProfileCubit>.value(value: profile),
          ],
          child: MaterialApp.router(
            theme: AppPreset.shipped.lightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const MeasurementDayNewPage(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the weight: the ruler, the last weigh-in, Next', (tester) async {
    await show(tester, start);

    expect(find.text('Measurement day'), findsOneWidget);
    // The heading only; the ruler draws no label of its own.
    expect(find.text('Weight'), findsOneWidget);
    // P5: the ruler sits low, near the bottom bar.
    expect(
      tester.getTopLeft(find.byType(NumberPicker)).dy,
      greaterThan(tester.getBottomLeft(find.text('Weight')).dy + 200),
    );
    final progress = tester.widget<StepProgress>(find.byType(StepProgress));
    expect((progress.count, progress.current), (3, 1));
    expect(progress.caption, 'Step 1 of 3 · Weight');
    expect(tester.widget<NumberPicker>(find.byType(NumberPicker)).value, 82.9);
    expect(find.textContaining('Last: 83.2 kg on '), findsOneWidget);
    // MD12: the track icon only on the measurements.
    expect(find.bySemanticsLabel('Measurements to track'), findsNothing);
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text('Next · measurements'));
    verify(() => cubit.next()).called(1);
  });

  testWidgets('the measurements: a row each, pairs side by side, the range '
      'under an invalid one', (tester) async {
    await show(
      tester,
      start.copyWith(
        step: MeasureStep.measurements,
        measurements: {BodyMeasurement.waist: '3'},
        invalidMeasurements: {BodyMeasurement.waist},
      ),
    );

    expect(find.text('Step 2 of 3 · Measurements'), findsOneWidget);
    expect(find.bySemanticsLabel('Measurements to track'), findsOneWidget);
    final rows = tester.widgetList<ListRow>(find.byType(ListRow)).toList();
    expect(rows.map((row) => row.title), [
      'Waist',
      'Upper arm',
      'Estimate body fat',
    ]);
    expect(rows[0].error, 'Enter a value from 10 to 250 cm');
    expect(rows[0].onInfo, isNotNull);
    final sides = tester
        .widgetList<ForgeNumberField>(find.byType(ForgeNumberField))
        .map((field) => field.side);
    expect(sides, [null, 'Left', 'Right']);

    await tester.enterText(find.byType(EditableText).first, '34');
    verify(() => cubit.setMeasurement(BodyMeasurement.waist, '34')).called(1);

    await tester.tap(find.text('Back'));
    verify(() => cubit.back()).called(1);
  });

  testWidgets('an info icon opens the measurement\'s hint', (tester) async {
    await show(tester, start.copyWith(step: MeasureStep.measurements));

    tester.widgetList<ListRow>(find.byType(ListRow)).first.onInfo!();
    await tester.pumpAndSettle();

    expect(find.byType(ForgeBottomSheet), findsOneWidget);
    expect(find.textContaining('narrowest point'), findsOneWidget);
  });

  testWidgets('the photos: four tiles; a tile opens the camera', (
    tester,
  ) async {
    await show(tester, start.copyWith(step: MeasureStep.photos));

    expect(find.text('Step 3 of 3 · Photos'), findsOneWidget);
    expect(find.textContaining('Same light, same spot.'), findsOneWidget);
    expect(find.byType(PhotoTile), findsNWidgets(4));
    expect(find.text('Add photo'), findsNWidgets(4));
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Left side'));
    verify(() => cubit.openCamera(PhotoPose.left)).called(1);
  });

  testWidgets('the camera opens in the frame on the last photo; Skip this '
      'photo closes it', (tester) async {
    await show(
      tester,
      start.copyWith(
        step: MeasureStep.photos,
        camera: () => PhotoPose.right,
        ghosts: {PhotoPose.right: '/photos/right.jpg'},
      ),
    );

    expect(find.byType(StepProgress), findsOneWidget);
    final camera = tester.widget<PoseCamera>(find.byType(PoseCamera));
    expect(camera.pose, 'Right side');
    expect((camera.step, camera.total), (2, 4));
    expect(camera.ghostFile, '/photos/right.jpg');

    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pumpAndSettle();
    verify(() => cubit.photoTaken('/tmp/0.jpg')).called(1);

    await tester.tap(find.text('Skip this photo'));
    verify(() => cubit.closeCamera()).called(1);
  });

  testWidgets('each step opens at the top', (tester) async {
    final states = StreamController<MeasurementDayState>();
    addTearDown(states.close);
    final measurements = start.copyWith(
      step: MeasureStep.measurements,
      groups: [
        for (final measurement in BodyMeasurement.values) [measurement],
      ],
    );
    await show(tester, measurements, states: states.stream);
    // Short enough for the measurements to scroll.
    tester.view.physicalSize = const Size(390 * 3, 700 * 3);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3 · Measurements'), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );

    states.add(measurements.copyWith(step: MeasureStep.photos));
    await tester.pumpAndSettle();

    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    expect(find.textContaining('Same light, same spot.'), findsOneWidget);
  });
}
