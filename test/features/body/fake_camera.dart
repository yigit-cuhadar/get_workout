import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const backCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const frontCamera = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

/// The camera plugin in tests: [cameras] open at once, or fail with
/// [initError]; each picture is `/tmp/<camera id>.jpg`. Camera ids are
/// the index into [opened].
class FakeCameraPlatform extends CameraPlatform {
  FakeCameraPlatform(this.cameras);

  final List<CameraDescription> cameras;
  final opened = <CameraDescription>[];
  CameraException? initError;
  int pictures = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    opened.add(cameraDescription);
    return opened.length - 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    if (initError case final error?) throw error;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1080,
          1920,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      StreamController<DeviceOrientationChangedEvent>().stream;

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}

  @override
  Future<XFile> takePicture(int cameraId) async {
    pictures++;
    return XFile('/tmp/$cameraId.jpg');
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> dispose(int cameraId) async {}
}
