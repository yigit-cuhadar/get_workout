import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/progress/domain/body_snapshot.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class MockBodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

void main() {
  late MockBodyListCubit bodyList;
  late StreamController<BodyListState> states;
  late DateTime now;
  late FakePremium premium;

  final august = BodyEntry(id: 'a', date: DateTime(2026, 8, 25), weightKg: 85);
  final november = BodyEntry(
    id: 'n',
    date: DateTime(2026, 11, 10),
    weightKg: 80,
  );
  final ready = BodyListState(
    status: BodyListStatus.ready,
    entries: [november, august],
  );

  setUp(() {
    now = DateTime(2026, 11, 13, 12);
    premium = FakePremium();
    bodyList = MockBodyListCubit();
    states = StreamController<BodyListState>.broadcast();
    whenListen(bodyList, states.stream, initialState: const BodyListState());
  });

  tearDown(() => states.close());

  ProgressBodyCubit build() => ProgressBodyCubit(
    bodyList: bodyList,
    watchPremium: WatchPremium(premium),
    clock: () => now,
  );

  test('follows the body list as a snapshot of its last 2 weeks', () async {
    final cubit = build();
    expect(cubit.state, const ProgressBodyState());

    when(() => bodyList.state).thenReturn(ready);
    states.add(ready);
    await pumpEventQueue();

    expect(
      cubit.state,
      ProgressBodyState(
        status: BodyListStatus.ready,
        snapshot: BodySnapshot(
          latest: (date: DateTime(2026, 11, 10), kg: 80.0),
          weights: [(date: DateTime(2026, 11, 10), kg: 80.0)],
        ),
      ),
    );
    await cubit.close();
  });

  test('with Premium its last 12 weeks, again when it goes', () async {
    final cubit = build();
    when(() => bodyList.state).thenReturn(ready);
    states.add(ready);
    premium.controller.add(true);
    await pumpEventQueue();

    expect(
      cubit.state.snapshot,
      BodySnapshot(
        latest: (date: DateTime(2026, 11, 10), kg: 80.0),
        weights: [
          (date: DateTime(2026, 8, 25), kg: 85.0),
          (date: DateTime(2026, 11, 10), kg: 80.0),
        ],
        weeks: 12,
      ),
    );

    premium.controller.add(false);
    await pumpEventQueue();
    expect(cubit.state.snapshot.weeks, 2);
    expect(cubit.state.snapshot.weights, hasLength(1));
    await cubit.close();
  });

  test('refreshNow moves the 12 weeks on to today', () async {
    final cubit = build();
    premium.controller.add(true);
    when(() => bodyList.state).thenReturn(ready);
    states.add(ready);
    await pumpEventQueue();
    expect(cubit.state.snapshot.weights, hasLength(2));

    // A week later 25 August is more than 12 weeks back.
    now = DateTime(2026, 11, 20, 8);
    cubit.refreshNow();

    expect(cubit.state.snapshot.weights, [
      (date: DateTime(2026, 11, 10), kg: 80.0),
    ]);
    expect(cubit.state.snapshot.latest?.kg, 80);
    await cubit.close();
  });

  test('retry retries the body list', () async {
    final cubit = build();
    cubit.retry();
    verify(() => bodyList.retry()).called(1);
    await cubit.close();
  });
}
