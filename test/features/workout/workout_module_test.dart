import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/volume_module.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/workout_module.dart';

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());

  tearDown(() => sl.reset());

  // GetIt throws on a second registration of a type, which would otherwise
  // only show at app start.
  test('the workout and volume modules register each type once', () {
    const WorkoutModule().register(sl);
    const VolumeModule().register(sl);

    expect(sl.isRegistered<WatchWorkoutsBetween>(), isTrue);
    expect(sl.isRegistered<WatchWeeklyVolume>(), isTrue);
  });
}
