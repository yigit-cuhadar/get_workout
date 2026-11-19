import 'package:flutter/material.dart';

/// What a premium call to action does: the subscription feature's paywall.
class PremiumPrompt {
  const PremiumPrompt(this.show);

  final void Function(BuildContext context) show;
}
