import 'dart:math' as math;

import '../domain/weekly_volume.dart';

/// The sets a chart reaches at least, so the band always shows with room
/// above it.
const _minScale = VolumeRange.max * 1.25;

/// The top of a scale holding every value of [sets].
double volumeScale(Iterable<double> sets) => sets.fold(_minScale, math.max);
