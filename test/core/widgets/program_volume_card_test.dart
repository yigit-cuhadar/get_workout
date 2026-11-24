import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/widgets/program_volume_card.dart';
import 'package:get_workout/core/widgets/volume_band.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import '../../component_harness.dart';

void main() {
  var taps = 0;

  Future<void> show(WidgetTester tester) => pumpComponent(
    tester,
    ProgramVolumeCard(
      sets: const {
        Muscle.pec: 14,
        Muscle.lat: 12,
        Muscle.frontDelt: 22,
        Muscle.triceps: 12,
        Muscle.biceps: 6,
        Muscle.calf: 0,
      },
      total: 96,
      onTap: () => taps++,
    ),
  );

  testWidgets('the title and the total in sets', (tester) async {
    await show(tester);

    expect(find.text('Weekly sets in this program'), findsOneWidget);
    expect(find.text('96 sets'), findsOneWidget);
  });

  testWidgets('the busiest major muscles as bands, in body order', (
    tester,
  ) async {
    await show(tester);

    final bands = tester.widgetList<VolumeBand>(find.byType(VolumeBand));
    expect(
      [for (final band in bands) band.muscle],
      // Triceps and biceps are small muscles: the full list has them.
      [Muscle.pec, Muscle.lat, Muscle.frontDelt],
    );
    expect({for (final band in bands) band.scale}, {25});
  });

  testWidgets('full-width bars, no body model', (tester) async {
    await show(tester);

    // The card's width less its 14px padding on each side.
    expect(
      tester.getSize(find.byType(VolumeBand).first).width,
      tester.getSize(find.byType(ProgramVolumeCard)).width - 28,
    );
  });

  testWidgets('a tap opens the full list', (tester) async {
    taps = 0;
    await show(tester);

    await tester.tap(find.text('Weekly sets in this program'));

    expect(taps, 1);
  });
}
