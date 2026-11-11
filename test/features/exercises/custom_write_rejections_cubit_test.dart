import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/presentation/custom_write_rejections_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

void main() {
  late StreamController<Failure> rejected;
  late MockCustomExerciseRepository repository;

  setUp(() {
    rejected = StreamController.broadcast();
    repository = MockCustomExerciseRepository();
    when(() => repository.rejectedWrites).thenAnswer((_) => rejected.stream);
  });

  tearDown(() => rejected.close());

  blocTest<CustomWriteRejectionsCubit, bool>(
    'a refused write is flagged until shown',
    build: () => CustomWriteRejectionsCubit(
      WatchRejectedCustomExerciseWrites(repository),
    ),
    act: (cubit) async {
      rejected.add(const PermissionFailure());
      await pumpEventQueue();
      cubit.shown();
    },
    expect: () => [true, false],
  );
}
