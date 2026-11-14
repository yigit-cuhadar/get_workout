import 'package:bloc_test/bloc_test.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/unsaved_changes.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/presentation/measurement_day_cubit.dart';
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

void main() {
  late _MeasurementDayCubit cubit;

  const steps = [
    WeightStep(),
    PhotoStep(PhotoPose.front),
    PhotoStep(PhotoPose.right),
    PhotoStep(PhotoPose.left),
    PhotoStep(PhotoPose.back),
  ];

  setUp(() {
    CameraPlatform.instance = FakeCameraPlatform([backCamera, frontCamera]);
    cubit = _MeasurementDayCubit();
    when(() => cubit.hasChanges).thenReturn(false);
    when(() => cubit.skip()).thenAnswer((_) async {});
    sl.registerFactoryParam<MeasurementDayCubit, MeasurementDaySetup, void>(
      (_, _) => cubit,
    );
  });

  tearDown(sl.reset);

  Future<void> show(WidgetTester tester, MeasurementDayState state) async {
    when(() => cubit.state).thenReturn(state);
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

  testWidgets('a photo step opens the pose camera on the last photo', (
    tester,
  ) async {
    await show(
      tester,
      const MeasurementDayState(
        steps: steps,
        index: 2,
        ghosts: {PhotoPose.right: '/photos/right.jpg'},
      ),
    );

    final camera = tester.widget<PoseCamera>(find.byType(PoseCamera));
    expect(camera.pose, 'Right side');
    expect((camera.step, camera.total), (2, 4));
    expect(camera.ghostFile, '/photos/right.jpg');
  });

  testWidgets('the photo taken goes to the flow', (tester) async {
    await show(tester, const MeasurementDayState(steps: steps, index: 1));

    await tester.tap(find.bySemanticsLabel('Take photo'));
    await tester.pumpAndSettle();

    verify(() => cubit.photoTaken('/tmp/0.jpg')).called(1);
  });

  testWidgets('a photo can be skipped', (tester) async {
    await show(tester, const MeasurementDayState(steps: steps, index: 4));

    await tester.tap(find.text('Skip'));
    await tester.pump();

    verify(() => cubit.skip()).called(1);
  });

  testWidgets('a taken photo shows with Retake, which reopens the camera', (
    tester,
  ) async {
    await show(
      tester,
      const MeasurementDayState(
        steps: steps,
        index: 1,
        newPhotos: {PhotoPose.front: '/tmp/front.jpg'},
      ),
    );
    expect(find.byType(PoseCamera), findsNothing);

    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();

    expect(find.byType(PoseCamera), findsOneWidget);
  });
}
