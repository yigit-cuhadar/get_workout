import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// Shows a [ForgeSnackbar] for an error over a bottom sheet, where
/// `showForgeSnackbar` would draw it on the page under the sheet: at the
/// bottom of the overlay the sheet lives in, as `showForgeSnackbar` places
/// it, for 4 s. A State that shows one disposes it with itself.
class SheetSnackbar {
  OverlayEntry? _entry;
  Timer? _timer;

  void show(BuildContext context, String message) {
    dispose();
    final entry = OverlayEntry(
      builder: (context) {
        final bottom = MediaQuery.of(context).viewPadding.bottom;
        return Positioned(
          left: Gap.md,
          right: Gap.md,
          bottom: Gap.md + bottom,
          child: Material(
            type: MaterialType.transparency,
            child: Semantics(
              liveRegion: true,
              child: ForgeSnackbar(message: message, error: true),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(entry);
    _entry = entry;
    _timer = Timer(const Duration(seconds: 4), dispose);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}
