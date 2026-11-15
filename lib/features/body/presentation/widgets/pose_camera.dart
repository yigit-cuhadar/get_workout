import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forge_camera/forge_camera.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';

/// The measurement-day camera on forge_camera's [GhostCamera]: a dark
/// viewfinder with the [pose] (to match the last photo, or the first one)
/// and the [step] of [total] on top, the preview in its own aspect ratio under a rule-of-thirds grid with the
/// [ghostFile] (the last photo of this pose) or, without one, a dashed
/// guide pose, and the 3 s timer, the shutter and the switch-camera
/// button on the bottom bar. The back camera comes first. A picture taken
/// goes to [onCaptured] as the path of a temporary file. Without camera
/// access the page offers the system settings and [onSkip]; without a
/// camera, [onSkip] alone.
class PoseCamera extends StatefulWidget {
  const PoseCamera({
    super.key,
    required this.pose,
    required this.step,
    required this.total,
    this.ghostFile,
    required this.onCaptured,
    required this.onSkip,
  });

  final String pose;
  final int step;
  final int total;
  final String? ghostFile;
  final ValueChanged<String> onCaptured;

  /// Goes on without this photo.
  final VoidCallback onSkip;

  /// The timer's count, in seconds.
  static const countdown = 3;

  @override
  State<PoseCamera> createState() => _PoseCameraState();
}

// The viewfinder is dark in every preset, as the card draws it.
const _frame = Color(0xFF101213);
const _preview = Color(0xFF1E2226);
const _light = Color(0xFFFFFFFF);
final _soft = _light.withValues(alpha: 0.16);

class _PoseCameraState extends State<PoseCamera> {
  final _camera = GhostCameraController();
  bool _timerOn = false;

  /// Seconds left while the timer counts down.
  int? _left;
  Timer? _ticker;
  bool _taking = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _camera.dispose();
    super.dispose();
  }

  void _shutter() {
    if (_left != null || _taking) return;
    if (!_timerOn) {
      unawaited(_take());
      return;
    }
    setState(() => _left = PoseCamera.countdown);
    _ticker = Timer.periodic(const Duration(seconds: 1), (ticker) {
      final left = _left! - 1;
      if (left > 0) {
        setState(() => _left = left);
        return;
      }
      ticker.cancel();
      unawaited(_take());
    });
  }

  Future<void> _take() async {
    setState(() => _taking = true);
    final path = await _camera.capture();
    if (!mounted) return;
    setState(() {
      _taking = false;
      _left = null;
    });
    if (path != null) widget.onCaptured(path);
  }

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ghost = widget.ghostFile;
    final left = _left;
    return ListenableBuilder(
      listenable: _camera,
      builder: (context, _) {
        final status = _camera.status;
        final busy = left != null || _taking;
        final viewfinder = ColoredBox(
          color: _frame,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  child: Row(
                    spacing: 6,
                    children: [
                      Expanded(
                        child: Text(
                          ghost == null
                              ? l10n.poseCameraFirstPhoto(widget.pose)
                              : l10n.poseCameraMatchLast(widget.pose),
                          style: text.bodyMedium!.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _light,
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: 0.7,
                        child: Text(
                          l10n.poseCameraStep(widget.step, widget.total),
                          style: style.data.copyWith(color: _light),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: _preview,
                  child: GhostCamera(
                    controller: _camera,
                    ghostFile: ghost,
                    overlay: Stack(
                      fit: StackFit.expand,
                      children: [
                        const IgnorePointer(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        if (ghost == null)
                          Center(
                            child: Semantics(
                              image: true,
                              label: l10n.poseCameraGuide,
                              child: const CustomPaint(
                                size: Size(150, 258),
                                painter: _GuidePainter(),
                              ),
                            ),
                          ),
                        if (left != null)
                          Center(
                            child: Text(
                              '$left',
                              style: style.dataLg.copyWith(
                                fontSize: 96,
                                height: 1,
                                fontWeight: FontWeight.w500,
                                color: _light,
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 2),
                                    blurRadius: 12,
                                    color: _frame.withValues(alpha: 0.4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 96,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _TimerToggle(
                            on: _timerOn,
                            onTap: () => setState(() => _timerOn = !_timerOn),
                          ),
                        ),
                      ),
                      _Shutter(
                        label: l10n.bodyTakePhoto,
                        onTap: status == GhostCameraStatus.ready && !busy
                            ? _shutter
                            : null,
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _camera.canSwitch
                              ? _SwitchButton(
                                  label: l10n.bodySwitchCamera,
                                  onTap: busy
                                      ? null
                                      : () => unawaited(_camera.switchCamera()),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        final prompt = switch (status) {
          GhostCameraStatus.accessDenied => PermissionPrompt.refused(
            title: l10n.poseCameraAccessOffTitle,
            message: l10n.poseCameraAccessOff,
            settingsLabel: l10n.poseCameraOpenSettings,
            onOpenSettings: () => unawaited(openSettings()),
            // The card's text button under Open settings.
            askAgainLabel: l10n.poseCameraSkipPhoto,
            onAskAgain: widget.onSkip,
          ),
          GhostCameraStatus.noCamera => PermissionPrompt.unavailable(
            icon: ForgeIcons.noPhotography,
            title: l10n.poseCameraNoCameraTitle,
            message: l10n.poseCameraNoCamera,
            skipLabel: l10n.poseCameraSkipPhoto,
            onSkip: widget.onSkip,
          ),
          _ => null,
        };
        final unavailable = prompt != null;
        return ClipRRect(
          borderRadius: BorderRadius.circular(style.radii.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Stays mounted while unavailable, so the camera opens again
              // when the app comes back with access.
              Offstage(offstage: unavailable, child: viewfinder),
              if (unavailable)
                ColoredBox(
                  color: style.colors.ground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 52,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.md,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.pose,
                              style: text.bodyMedium!.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: prompt,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The 3 s timer as a pill: soft white when off, white with dark ink when
/// on.
class _TimerToggle extends StatelessWidget {
  const _TimerToggle({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final l10n = AppLocalizations.of(context);
    final ink = on ? _frame : _light;
    return Semantics(
      button: true,
      toggled: on,
      label: on
          ? l10n.poseCameraTimerOn(PoseCamera.countdown)
          : l10n.poseCameraTimerOff(PoseCamera.countdown),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? _light : _soft,
                borderRadius: BorderRadius.circular(style.radii.lg),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 5,
                children: [
                  ForgeIcon(ForgeIcons.timer, size: 16, color: ink),
                  Text(
                    l10n.poseCameraTimer(PoseCamera.countdown),
                    style: style.data.copyWith(
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white ring around a white disc; dimmed while it cannot be pressed.
class _Shutter extends StatelessWidget {
  const _Shutter({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _light, width: 3),
          ),
          child: Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _light,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _soft),
        child: const ForgeIcon(ForgeIcons.flipCamera, size: 24, color: _light),
      ),
    ),
  );
}

/// Lines at the thirds of the preview.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _soft
      ..strokeWidth = 1;
    for (final third in [1 / 3, 2 / 3]) {
      final x = size.width * third;
      final y = size.height * third;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), line)
        ..drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// A standing figure, faintly filled with a dashed edge, where no earlier
/// photo of the pose exists.
class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  /// The figure's own box.
  static const _box = Size(140, 240);

  static final Path _figure = Path()
    ..addOval(Rect.fromCircle(center: const Offset(70, 28), radius: 16))
    ..moveTo(41, 54)
    ..quadraticBezierTo(70, 46, 99, 54)
    ..lineTo(113, 140)
    ..lineTo(103, 142)
    ..lineTo(95, 100)
    ..lineTo(93, 140)
    ..lineTo(82, 232)
    ..lineTo(72, 232)
    ..lineTo(70, 150)
    ..lineTo(68, 232)
    ..lineTo(58, 232)
    ..lineTo(47, 140)
    ..lineTo(45, 100)
    ..lineTo(37, 142)
    ..lineTo(27, 140)
    ..close();

  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _box.width, size.height / _box.height);
    canvas.drawPath(_figure, Paint()..color = _light.withValues(alpha: 0.12));
    final edge = Paint()
      ..color = _light.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final ui.PathMetric metric in _figure.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), edge);
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => false;
}
