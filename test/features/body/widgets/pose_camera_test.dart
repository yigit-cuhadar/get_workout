import 'dart:convert';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/presentation/widgets/pose_camera.dart';

import '../../../core/widgets/component_harness.dart';
import '../fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;
  late List<String> captured;

  setUp(() {
    platform = FakeCameraPlatform([backCamera, frontCamera]);
    CameraPlatform.instance = platform;
    captured = [];
  });

  Future<void> show(WidgetTester tester, {String? ghostFile}) async {
    await pumpComponent(
      tester,
      SizedBox(
        height: 600,
        child: PoseCamera(
          pose: 'Right side',
          step: 2,
          total: 4,
          ghostFile: ghostFile,
          onCaptured: captured.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.bySemanticsLabel(label);

  testWidgets('names the pose and its step, back camera first', (tester) async {
    await show(tester);

    expect(find.text('Right side'), findsOneWidget);
    expect(find.text('2 / 4'), findsOneWidget);
    expect(platform.opened, [backCamera]);
  });

  testWidgets('without a last photo it shows the guide pose', (tester) async {
    await show(tester);

    expect(button('Guide pose'), findsOneWidget);
  });

  testWidgets('with a last photo the ghost replaces the guide', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ghost');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ghost = File('${dir.path}/ghost.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
        ),
      );
    await show(tester, ghostFile: ghost.path);

    expect(button('Guide pose'), findsNothing);
  });

  testWidgets('the shutter takes the photo at once', (tester) async {
    await show(tester);

    await tester.tap(button('Take photo'));
    await tester.pumpAndSettle();

    expect(captured, ['/tmp/0.jpg']);
  });

  testWidgets('with the timer on the shutter counts 3 s first', (tester) async {
    await show(tester);

    await tester.tap(button('3 second timer, off'));
    await tester.pump();
    expect(button('3 second timer, on'), findsOneWidget);

    await tester.tap(button('Take photo'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(
      tester.getSemantics(button('Take photo')),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        label: 'Take photo',
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    expect(platform.pictures, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(captured, ['/tmp/0.jpg']);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('a tap while counting takes no second photo', (tester) async {
    await show(tester);
    await tester.tap(button('3 second timer, off'));
    await tester.pump();

    await tester.tap(button('Take photo'));
    await tester.pump();
    await tester.tap(button('Take photo'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(platform.pictures, 1);
  });

  testWidgets('switch camera opens the other lens', (tester) async {
    await show(tester);

    await tester.tap(button('Switch camera'));
    await tester.pumpAndSettle();

    expect(platform.opened, [backCamera, frontCamera]);
  });

  testWidgets('one camera: no switch button', (tester) async {
    CameraPlatform.instance = platform = FakeCameraPlatform([backCamera]);
    await show(tester);

    expect(button('Switch camera'), findsNothing);
  });

  testWidgets('camera access off says so', (tester) async {
    platform.initError = CameraException('CameraAccessDenied', 'denied');
    await show(tester);

    expect(find.text("The camera isn't available"), findsOneWidget);
    expect(find.text('Right side'), findsOneWidget);
  });

  testWidgets('no camera says so', (tester) async {
    CameraPlatform.instance = platform = FakeCameraPlatform([]);
    await show(tester);

    expect(find.text("The camera isn't available"), findsOneWidget);
  });
}
