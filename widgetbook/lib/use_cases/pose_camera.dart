import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/body/presentation/widgets/pose_camera.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

// The states follow the device's camera: the 3 s timer and the shutter
// show the countdown, refusing camera access shows the access-off state,
// a device without a camera the no-camera one. A last photo cannot show
// on the web (it is a file), so this is the first photo with its guide.

@widgetbook.UseCase(name: 'Live camera, first photo', type: PoseCamera)
Widget poseCamera(BuildContext context) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: SizedBox(
    height: 480,
    child: PoseCamera(
      pose: context.knobs.string(label: 'Pose', initialValue: 'Front'),
      step: context.knobs.int.slider(
        label: 'Step',
        initialValue: 1,
        min: 1,
        max: 4,
      ),
      total: 4,
      onCaptured: (_) {},
    ),
  ),
);
