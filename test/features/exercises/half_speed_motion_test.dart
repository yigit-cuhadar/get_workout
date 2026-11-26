import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/features/exercises/presentation/widgets/exercise_motion_view.dart';

/// Writes the sampled time in milliseconds into every value.
class _Clock implements ModelMotion {
  @override
  Duration get duration => const Duration(seconds: 3);

  @override
  final bounds = Float64List.fromList([-1, 0, -1, 1, 2, 1]);

  @override
  int get jointCount => 2;

  @override
  int get markerCount => 1;

  @override
  void sample(Duration time, Float32List out) =>
      out.fillRange(0, out.length, time.inMilliseconds.toDouble());

  @override
  void sampleMarkers(Duration time, Float32List out) =>
      out.fillRange(0, out.length, time.inMilliseconds.toDouble());
}

void main() {
  test('a loop takes twice as long and samples at half the time', () {
    final clip = _Clock();
    final slow = HalfSpeedMotion(clip);
    final pose = Float32List(slow.jointCount * 12);
    final markers = Float32List(slow.markerCount * 3);

    slow
      ..sample(const Duration(milliseconds: 1000), pose)
      ..sampleMarkers(const Duration(milliseconds: 1000), markers);

    expect(slow.duration, const Duration(seconds: 6));
    expect(pose.toSet(), {500});
    expect(markers.toSet(), {500});
    expect((slow.jointCount, slow.markerCount), (2, 1));
    expect(slow.bounds, clip.bounds);
  });
}
