import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_ui/forge_ui.dart';

/// Sends touches within a [ForgeTheme.tapMin] square around each
/// [TapBand] inside [child] to that control, though it is drawn smaller
/// and the layout stays as drawn (as Forge's ListRow does for its info
/// icon). Where two bands overlap, the control nearer the touch takes it.
class TapBandArea extends SingleChildRenderObjectWidget {
  const TapBandArea({super.key, required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderTapBandArea();
}

/// A control drawn smaller than [ForgeTheme.tapMin] whose [TapBandArea]
/// gives it a full tap band. The band takes touches only while the control
/// is drawn whole: one scrolled partly or fully out of view, or hidden,
/// takes only the touches that land on what is drawn of it.
class TapBand extends SingleChildRenderObjectWidget {
  const TapBand({super.key, required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => _RenderTapBand();
}

class _RenderTapBand extends RenderProxyBox {
  _RenderTapBandArea? _area;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var node = parent;
    while (node != null && node is! _RenderTapBandArea) {
      node = node.parent;
    }
    _area = node as _RenderTapBandArea?;
    _area?.bands.add(this);
  }

  @override
  void detach() {
    _area?.bands.remove(this);
    _area = null;
    super.detach();
  }

  /// Whether every ancestor up to [area] paints this band and none of them
  /// clips any of it.
  bool _drawnWholeIn(_RenderTapBandArea area) {
    RenderObject child = this;
    var node = parent;
    while (node != null && node != area) {
      if (!node.paintsChild(child)) return false;
      if (node.describeApproximatePaintClip(child) case final clip?) {
        final box = MatrixUtils.transformRect(
          getTransformTo(node),
          Offset.zero & size,
        );
        final drawn = clip.intersect(box);
        // A hair's tolerance for rounding in the transforms.
        if (drawn.width < box.width - 0.5 || drawn.height < box.height - 0.5) {
          return false;
        }
      }
      child = node;
      node = node.parent;
    }
    return node == area;
  }
}

class _RenderTapBandArea extends RenderProxyBox {
  final bands = <_RenderTapBand>{};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      _RenderTapBand? nearest;
      Offset? nearestLocal;
      var nearestDistance = double.infinity;
      for (final band in bands) {
        if (!band.attached || !band.hasSize || !band._drawnWholeIn(this)) {
          continue;
        }
        final local = band.globalToLocal(localToGlobal(position));
        final centre = band.size.center(Offset.zero);
        final area = Rect.fromCenter(
          center: centre,
          width: max(ForgeTheme.tapMin, band.size.width),
          height: max(ForgeTheme.tapMin, band.size.height),
        );
        // From the drawn box: 0 on it, so a touch on a control is its own.
        final box = Offset.zero & band.size;
        final distance =
            (local -
                    Offset(
                      local.dx.clamp(box.left, box.right),
                      local.dy.clamp(box.top, box.bottom),
                    ))
                .distance;
        if (area.contains(local) && distance < nearestDistance) {
          nearest = band;
          nearestLocal = local;
          nearestDistance = distance;
        }
      }
      if (nearest != null) {
        // Off the drawn box, the touch lands on its centre.
        nearest.hitTest(
          result,
          position: nearest.size.contains(nearestLocal!)
              ? nearestLocal
              : nearest.size.center(Offset.zero),
        );
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return super.hitTest(result, position: position);
  }
}
