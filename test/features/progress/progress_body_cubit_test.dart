import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/progress/domain/body_snapshot.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockBodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

void main() {
  late MockBodyListCubit bodyList;
  late StreamController<BodyListState> states;
  late DateTime now;

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
    bodyList = MockBodyListCubit();
    states = StreamController<BodyListState>.broadcast();
    whenListen(bodyList, states.stream, initialState: const BodyListState());
  });

  tearDown(() => states.close());

  ProgressBodyCubit build() =>
      ProgressBodyCubit(bodyList: bodyList, clock: () => now);

  test('follows the body list as a snapshot of its last 12 weeks', () async {
    final cubit = build();
    expect(cubit.state, const ProgressBodyState());

    when(() => bodyList.state).thenReturn(ready);
    states.add(ready);
    await pumpEventQueue();

    expect(
      cubit.state,
      ProgressBodyState(
        status: BodyListStatus.ready,
        empty: false,
        snapshot: BodySnapshot(
          latestKg: 80,
          weights: [
            (date: DateTime(2026, 8, 25), kg: 85.0),
            (date: DateTime(2026, 11, 10), kg: 80.0),
          ],
        ),
      ),
    );
    await cubit.close();
  });

  test('refreshNow moves the 12 weeks on to today', () async {
    final cubit = build();
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
    expect(cubit.state.snapshot.latestKg, 80);
    await cubit.close();
  });

  test('retry retries the body list', () async {
    final cubit = build();
    cubit.retry();
    verify(() => bodyList.retry()).called(1);
    await cubit.close();
  });
}
