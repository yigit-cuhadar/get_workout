import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/muscle_model.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import 'component_harness.dart';

void main() {
  late Model3D body;

  setUpAll(() async {
    body = await Model3D.fromGlb(
      File('assets/models/body_male.glb').readAsBytesSync(),
    );
  });

  Widget framed(Widget model) => SizedBox(height: 480, child: model);

  testWidgets('Front and Back turn the model', (tester) async {
    await pumpComponent(
      tester,
      framed(
        MuscleModel(model: body, onOpen: (_) {}, semanticLabel: 'Body model'),
      ),
    );
    bool front() => tester
        .widget<ForgeSegmentedControl<bool>>(
          find.byType(ForgeSegmentedControl<bool>),
        )
        .selected;

    expect(front(), isTrue);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(front(), isFalse);
    await tester.tap(find.text('Front'));
    await tester.pumpAndSettle();
    expect(front(), isTrue);
  });

  testWidgets('without sides there is no Front / Back', (tester) async {
    await pumpComponent(
      tester,
      framed(
        MuscleModel(
          model: body,
          onOpen: (_) {},
          semanticLabel: 'Body',
          sides: false,
        ),
      ),
    );

    expect(find.byType(ForgeSegmentedControl<bool>), findsNothing);
  });

  testWidgets('a tap on a muscle opens it', (tester) async {
    final opened = <Muscle>[];
    await pumpComponent(
      tester,
      framed(
        MuscleModel(model: body, onOpen: opened.add, semanticLabel: 'Body'),
      ),
    );

    tester.widget<ModelViewer>(find.byType(ModelViewer)).onPartTap!('pec_left');
    expect(opened, [Muscle.pec]);
  });

  testWidgets('a slide shows the muscle and its release opens it', (
    tester,
  ) async {
    final opened = <Muscle>[];
    await pumpComponent(
      tester,
      framed(
        MuscleModel(model: body, onOpen: opened.add, semanticLabel: 'Body'),
      ),
    );
    final viewer = tester.widget<ModelViewer>(find.byType(ModelViewer));

    viewer.onScrub!('pec_right');
    await tester.pump();
    expect(find.text('release to open'), findsOneWidget);
    expect(opened, isEmpty);

    viewer.onScrubEnd!('pec_right');
    await tester.pump();
    expect(find.text('release to open'), findsNothing);
    expect(opened, [Muscle.pec]);
  });

  testWidgets('an interrupted slide opens nothing', (tester) async {
    final opened = <Muscle>[];
    await pumpComponent(
      tester,
      framed(
        MuscleModel(model: body, onOpen: opened.add, semanticLabel: 'Body'),
      ),
    );
    final viewer = tester.widget<ModelViewer>(find.byType(ModelViewer));

    viewer.onScrub!('pec_right');
    viewer.onScrubEnd!(null);
    await tester.pump();
    expect(opened, isEmpty);
  });

  testWidgets('loading shows a shimmering figure', (tester) async {
    await pumpComponent(tester, framed(const MuscleModel.loading()));

    expect(find.byType(SkeletonBar), findsNWidgets(4));
    expect(find.byType(ModelViewer), findsNothing);
  });

  testWidgets('a failed model offers Retry', (tester) async {
    var retried = 0;
    await pumpComponent(
      tester,
      framed(MuscleModel.failed(onRetry: () => retried++)),
    );

    expect(find.text("Couldn't load the model"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('side by side: front and back with the legend', (tester) async {
    await pumpComponent(
      tester,
      MuscleModelPair(
        model: body,
        title: 'Worked muscles',
        main: const [Muscle.pec],
        secondary: const [Muscle.frontDelt, Muscle.triceps],
      ),
    );

    expect(find.byType(ModelViewer), findsNWidgets(2));
    for (final text in [
      'Worked muscles',
      'Front',
      'Back',
      'Main',
      'Secondary',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    final viewers = tester.widgetList<ModelViewer>(find.byType(ModelViewer));
    expect(viewers.every((viewer) => !viewer.interactive), isTrue);
  });
}
