import 'package:forge_core/forge_core.dart';

/// A body measurement, in cm. [code] is its key in an entry's
/// `measurements` map.
enum BodyMeasurement {
  neck('neck'),
  shoulders('shoulders'),
  chest('chest'),
  waist('waist'),
  abdomen('abdomen'),
  hips('hips'),
  leftUpperArm('leftUpperArm'),
  rightUpperArm('rightUpperArm'),
  leftForearm('leftForearm'),
  rightForearm('rightForearm'),
  leftThigh('leftThigh'),
  rightThigh('rightThigh'),
  leftCalf('leftCalf'),
  rightCalf('rightCalf');

  const BodyMeasurement(this.code);
  final String code;

  /// Tracked until the user chooses their own.
  static const standard = {
    chest,
    waist,
    hips,
    leftUpperArm,
    rightUpperArm,
    leftThigh,
    rightThigh,
  };

  /// Null for unknown codes, e.g. from a newer app version.
  static BodyMeasurement? fromCode(Object? code) {
    for (final measurement in values) {
      if (measurement.code == code) return measurement;
    }
    return null;
  }

  /// The right side of a left one; null for every other measurement.
  BodyMeasurement? get rightSide => switch (this) {
    leftUpperArm => rightUpperArm,
    leftForearm => rightForearm,
    leftThigh => rightThigh,
    leftCalf => rightCalf,
    _ => null,
  };
}

/// [measurements] in their usual order, grouped: a left and right side that
/// are both there form one group of two (left first), every other
/// measurement a group of its own.
List<List<BodyMeasurement>> pairedMeasurements(
  Set<BodyMeasurement> measurements,
) {
  final rights = {
    for (final measurement in measurements)
      if (measurement.rightSide case final right?
          when measurements.contains(right))
        right,
  };
  return [
    for (final measurement in BodyMeasurement.values)
      if (measurements.contains(measurement) && !rights.contains(measurement))
        [
          measurement,
          if (measurement.rightSide case final right?
              when rights.contains(right))
            right,
        ],
  ];
}

/// The four progress photos of a measurement day, in the order they are
/// taken. [code] is its key in an entry's `photos` map and its file name.
enum PhotoPose {
  front('front'),
  right('right'),
  left('left'),
  back('back');

  const PhotoPose(this.code);
  final String code;

  static PhotoPose? fromCode(Object? code) {
    for (final pose in values) {
      if (pose.code == code) return pose;
    }
    return null;
  }
}

/// Where the [pose] photo of entry [entryId] lives: the Cloud Storage path
/// of its backup, and the same path inside the app's private storage.
/// [revision] (the capture time in ms) makes a retaken photo a new path, so
/// every device sees that its copy is out of date and fetches the new one.
String photoPath(String uid, String entryId, PhotoPose pose, int revision) =>
    'users/$uid/photos/$entryId/${pose.code}-$revision.jpg';

/// The folder of all of [uid]'s photos.
String photoFolder(String uid) => 'users/$uid/photos';

/// Whether [path] is one of [uid]'s photos.
bool isPhotoOf(String path, String uid) =>
    path.startsWith('${photoFolder(uid)}/');

/// One `bodyEntries` document. A quick weight log has only [weightKg]; a
/// measurement day may also have [measurements] and [photos].
class BodyEntry extends Equatable {
  const BodyEntry({
    required this.id,
    required this.date,
    this.weightKg,
    this.measurements = const {},
    this.photos = const {},
  });

  /// Made on the device before the entry is stored, so photos can be filed
  /// under it.
  final String id;
  final DateTime date;
  final double? weightKg;

  /// In cm.
  final Map<BodyMeasurement, double> measurements;

  /// Storage paths; see [photoPath].
  final Map<PhotoPose, String> photos;

  bool get isWeightOnly => measurements.isEmpty && photos.isEmpty;

  bool get isEmpty => weightKg == null && isWeightOnly;

  @override
  List<Object?> get props => [id, date, weightKg, measurements, photos];
}
