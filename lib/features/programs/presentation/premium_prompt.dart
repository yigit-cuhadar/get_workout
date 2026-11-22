import 'package:material_ui/material_ui.dart';

/// What a premium call to action does: the subscription feature's paywall.
class PremiumPrompt {
  const PremiumPrompt(this.show);

  /// Completes with whether the user has Premium afterwards.
  final Future<bool> Function(BuildContext context) show;
}
