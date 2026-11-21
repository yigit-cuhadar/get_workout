import 'package:flutter/widgets.dart';
import 'package:forge_ui/forge_ui.dart';

/// Who can read a program's days, as a tag: Premium in the info tint,
/// Free plain grey.
class AccessTag extends StatelessWidget {
  const AccessTag({super.key, required this.premium});

  final bool premium;

  @override
  Widget build(BuildContext context) => premium
      ? const ForgeTag('Premium', kind: ForgeTagKind.source)
      : const ForgeTag('Free');
}
