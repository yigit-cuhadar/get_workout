import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_it/get_it.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';
import 'package:get_workout/features/steps/presentation/steps_cubit.dart';
import 'package:get_workout/features/steps/steps_module.dart';

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());
  tearDown(() => sl.reset());

  bool fake(TargetPlatform platform, {required bool release}) {
    final sl = GetIt.asNewInstance();
    healthModule(platform: platform, release: release).register(sl);
    return sl.isRegistered<FakeHealthSteps>();
  }

  test('the platform store on iOS and Android, in every build', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(fake(platform, release: false), isFalse, reason: '$platform');
      expect(fake(platform, release: true), isFalse, reason: '$platform');
    }
  });

  test('the fake elsewhere in debug and profile, the store in release', () {
    expect(fake(TargetPlatform.macOS, release: false), isTrue);
    expect(fake(TargetPlatform.macOS, release: true), isFalse);
  });

  test('registers the page and the Today use case', () {
    HealthModule.fake(FakeHealthSteps()).register(sl);
    const StepsModule().register(sl);
    expect(sl<GetTodaySteps>(), isA<GetTodaySteps>());
    final cubit = sl<StepsCubit>();
    addTearDown(cubit.close);
  });
}
