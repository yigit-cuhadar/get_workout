import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/workout_bar.dart';

import '../../../../component_harness.dart';

void main() {
  testWidgets('is a MiniBar with the workout and its time; a tap opens it', (
    tester,
  ) async {
    var opened = 0;
    await pumpComponent(
      tester,
      WorkoutBar(name: 'Push', detail: 'Rest 1:12', onTap: () => opened++),
    );

    final bar = tester.widget<MiniBar>(find.byType(MiniBar));
    expect(bar.icon, ForgeIcons.fitnessCenter);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Rest 1:12'), findsOneWidget);
    await tester.tap(find.byType(WorkoutBar));
    expect(opened, 1);
  });
}
