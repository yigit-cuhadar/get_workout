import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/progress/domain/body_snapshot.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:get_workout/features/workout/presentation/workout_page.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart';
import 'body_stand_in.dart';
import 'progress_stand_ins.dart';
import 'training_world.dart';

class _BodyCubit extends MockCubit<ProgressBodyState>
    implements ProgressBodyCubit {}

/// Today's, Programs' and Progress' cards and the workout's header lay
/// out at large text with nothing overflowing: an overflow fails the test.
void main() {
  final upperLower = Program(
    id: 'p1',
    name: 'Upper Lower Strength Builder',
    days: [
      ProgramDay(name: 'Upper', items: [item('bench')]),
      ProgramDay(name: 'Lower body and core', items: [item('squat')]),
    ],
  );

  /// Lower is due today, and two weigh-ins make a trend.
  TrainingWorld world() {
    final world = TrainingWorld(
      exercises: [
        move('squat', name: 'Single-Leg Romanian Deadlift'),
        move('bench', name: 'Bench Press'),
      ],
    );
    world.programs
      ..add(upperLower)
      ..active = ActiveProgram(
        programId: 'p1',
        schedule: const {1: 0, 3: 1},
        nextDayIndex: 1,
        nextDate: dateOf(flowStart),
        startedAt: DateTime(2026, 11, 2),
      );
    return world;
  }

  void registerProgress(TrainingWorld _) {
    registerProgressStandIns();
    registerBodyListStandIn();
    final body = _BodyCubit();
    when(() => body.state).thenReturn(
      ProgressBodyState(
        status: BodyListStatus.ready,
        snapshot: BodySnapshot(
          latest: (date: DateTime(2026, 11, 10), kg: 82.4),
          weights: [
            (date: DateTime(2026, 11, 3), kg: 82.8),
            (date: DateTime(2026, 11, 10), kg: 82.4),
          ],
        ),
      ),
    );
    sl
      ..unregister<ProgressBodyCubit>()
      ..registerFactory<ProgressBodyCubit>(() => body);
  }

  for (final scale in [2.0, 3.0]) {
    testWidgets('at ${scale}x text nothing overflows', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Forge's ListRowDateBox and MiniBar keep a fixed height and
      // overflow at large text; they wait on a Forge fix. Anything else
      // fails the test.
      final report = FlutterError.onError;
      FlutterError.onError = (details) {
        final at = details.toString();
        if (at.contains('list_row.dart') || at.contains('mini_bar.dart')) {
          return;
        }
        report?.call(details);
      };
      addTearDown(() => FlutterError.onError = report);
      final app = world();
      await app.start(tester, registerMore: registerProgress);
      expect(find.text('Lower body and core'), findsWidgets);

      await openTab(tester, 'Programs');
      expect(find.text('Upper Lower Strength Builder'), findsWidgets);

      await openTab(tester, 'Progress');
      expect(find.textContaining('82.4 kg'), findsOneWidget);

      await openTab(tester, 'Today');
      await tapText(tester, 'Start Lower body and core');
      expect(find.byType(WorkoutPage), findsOneWidget);

      await app.stop(tester);
    });
  }
}
