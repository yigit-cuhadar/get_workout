import 'package:bloc_test/bloc_test.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/volume_band.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_volume_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../exercises/fixtures.dart';
import 'fixtures.dart';

class _ListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _ModelCubit extends MockCubit<BodyModelState> implements BodyModelCubit {}

void main() {
  late _ListCubit list;
  late _CatalogueCubit catalogue;

  setUp(() {
    list = _ListCubit();
    catalogue = _CatalogueCubit();
    sl.registerSingleton<ProgramListCubit>(list);
  });

  tearDown(sl.reset);

  Future<void> pump(
    WidgetTester tester, {
    required ProgramListState programs,
    required ExerciseCatalogueState exercises,
    BodyModelState body = const BodyModelFailed(),
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => list.state).thenReturn(programs);
    when(() => catalogue.state).thenReturn(exercises);
    final model = _ModelCubit();
    when(() => model.state).thenReturn(body);
    when(model.load).thenAnswer((_) async {});
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<BodyModelCubit>.value(value: model),
        ],
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProgramVolumePage(id: 'p1'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the program\'s weekly sets for every muscle', (
    tester,
  ) async {
    await pump(
      tester,
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
      ),
      exercises: CatalogueReady([
        exercise('a', main: [Muscle.quads]),
        exercise('b', main: [Muscle.pec]),
        exercise('c', main: [Muscle.quads]),
        exercise('d', main: [Muscle.quads]),
      ]),
    );

    expect(find.text('Upper Lower · per week'), findsOneWidget);
    expect(find.text('12 sets'), findsOneWidget);
    final bands = tester.widgetList<VolumeBand>(find.byType(VolumeBand));
    expect(bands.length, Muscle.values.length);
    expect(bands.first.muscle, Muscle.quads);
    expect(bands.first.sets, 9);
  });

  testWidgets('nothing opens a muscle: the model only turns', (tester) async {
    final body = await tester.runAsync(
      () async => Model3D.fromGlb(
        File('assets/models/body_male.glb').readAsBytesSync(),
      ),
    );
    await pump(
      tester,
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
      ),
      exercises: CatalogueReady([
        exercise('a', main: [Muscle.quads]),
      ]),
      body: BodyModelReady(body!),
    );

    expect(find.text('Drag to turn'), findsOneWidget);
    expect(
      tester.widget<ModelViewer>(find.byType(ModelViewer)).onPartTap,
      isNull,
    );
    expect(
      tester
          .widgetList<InkWell>(
            find.ancestor(
              of: find.byType(VolumeBand),
              matching: find.byType(InkWell),
            ),
          )
          .every((row) => row.onTap == null),
      isTrue,
    );
  });

  testWidgets('a program that is gone says so', (tester) async {
    await pump(
      tester,
      programs: const ProgramListState(status: ProgramListStatus.ready),
      exercises: const CatalogueLoading(),
    );

    expect(find.text('Program not found'), findsOneWidget);
  });

  testWidgets('a library that failed offers Retry', (tester) async {
    when(catalogue.retry).thenAnswer((_) async {});
    await pump(
      tester,
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
      ),
      exercises: const CatalogueFailed(UnknownFailure('offline')),
    );

    await tester.tap(find.text('Retry'));
    verify(catalogue.retry).called(1);
  });
}
