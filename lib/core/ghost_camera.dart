import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

/// A live camera preview with [ghostFile], an earlier picture, laid faintly
/// over it, so a new picture can be lined up with the old one. The shutter
/// hands the new picture to [onCaptured] as a temporary file; nothing is
/// written to the gallery. Starts on the back camera; a button switches
/// cameras when the device has more than one. Always portrait: the screen
/// is held upright while it shows, and the capture is locked to portrait,
/// so the preview, the ghost and the picture agree however the phone is
/// tilted. Knows nothing of what it takes; the caller writes every label.
// Belongs in a forge package; move it there when one next changes.
class GhostCamera extends StatefulWidget {
  const GhostCamera({
    super.key,
    required this.onCaptured,
    required this.captureLabel,
    required this.switchLabel,
    required this.unavailableText,
    this.ghostFile,
  });

  final ValueChanged<String> onCaptured;
  final String? ghostFile;
  final String captureLabel;
  final String switchLabel;

  /// Shown when there is no camera or access to it was refused.
  final String unavailableText;

  @override
  State<GhostCamera> createState() => _GhostCameraState();
}

class _GhostCameraState extends State<GhostCamera> {
  static const _ghostOpacity = 0.35;

  /// The cameras showing: one replacing another (the next pose) starts
  /// before the old one is disposed, so the screen is freed only after
  /// the last.
  static var _shown = 0;

  late final AppLifecycleListener _lifecycle;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _camera;
  CameraController? _controller;
  bool _unavailable = false;

  /// The cameras being closed; the next one opens after them.
  Future<void> _closing = Future.value();
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    if (_shown++ == 0) {
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
    // The camera is released while the app is away, as the platforms
    // require, and opened again on return.
    _lifecycle = AppLifecycleListener(
      onInactive: _release,
      onResume: () => unawaited(_open()),
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
    } on CameraException {
      _cameras = const [];
    }
    if (!mounted) return;
    _camera = _cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .followedBy(_cameras)
        .firstOrNull;
    await _open();
  }

  Future<void> _open() async {
    final camera = _camera;
    if (camera == null) {
      setState(() => _unavailable = true);
      return;
    }
    if (_controller != null) return;
    // A camera still closing would make this one fail to start.
    await _closing;
    if (!mounted || _controller != null) return;
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    try {
      await controller.initialize();
      // Without the lock, the plugin turns the capture, and the preview
      // with it, with the phone, also while the screen stays portrait.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (mounted) setState(() => _unavailable = false);
    } on Object {
      // Released again while starting: [_release] disposed it.
      if (_controller != controller) return;
      // Refused access, or no working camera.
      _controller = null;
      await _close(controller);
      if (mounted) setState(() => _unavailable = true);
    }
  }

  /// Disposing one that never finished starting throws (the system's
  /// permission prompt makes the app inactive mid-start); nothing to undo.
  Future<void> _close(CameraController controller) async {
    try {
      await controller.dispose();
    } on Object {
      // Already gone.
    }
  }

  void _release() {
    final controller = _controller;
    _controller = null;
    if (controller != null) _closing = _closing.then((_) => _close(controller));
    if (mounted) setState(() {});
  }

  Future<void> _switch() async {
    final current = _camera;
    if (current == null || _cameras.length < 2) return;
    _camera = _cameras[(_cameras.indexOf(current) + 1) % _cameras.length];
    _release();
    await _open();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final picture = await controller.takePicture();
      widget.onCaptured(picture.path);
    } on CameraException {
      // The preview stays; the user can try again.
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    if (--_shown == 0) {
      // Back to what the app declares.
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    _lifecycle.dispose();
    final controller = _controller;
    if (controller != null) unawaited(_close(controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return EmptyView(message: widget.unavailableText);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const LoadingView();
    }
    final ghost = widget.ghostFile;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: CameraPreview(
              controller,
              child: ghost == null
                  ? null
                  : IgnorePointer(
                      child: Opacity(
                        opacity: _ghostOpacity,
                        child: Transform.flip(
                          flipX: mirrorGhost(controller.description),
                          child: Image.file(
                            File(ghost),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              tooltip: widget.captureLabel,
              iconSize: Gap.xl,
              onPressed: _capturing ? null : _capture,
              icon: const Icon(Icons.camera_alt),
            ),
            if (_cameras.length > 1) ...[
              const SizedBox(width: Gap.md),
              IconButton(
                tooltip: widget.switchLabel,
                onPressed: _capturing ? null : _switch,
                icon: const Icon(Icons.cameraswitch),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Whether the ghost is flipped to match the preview of [camera]. Both
/// platforms show the front camera's preview mirrored, like a mirror, but
/// save its pictures unmirrored, as every ghost is; the back camera is
/// mirrored in neither. Verify on iOS and Android whenever the camera
/// plugin changes.
bool mirrorGhost(CameraDescription camera) =>
    camera.lensDirection == CameraLensDirection.front;
