import 'package:flutter/widgets.dart';
import 'package:forge_ui/forge_ui.dart';

/// The running workout shrunk above the navigation bar, as Forge's
/// [MiniBar]: the workout's [name], the elapsed time or the rest left as
/// [detail], and the up chevron. A tap opens the workout screen again.
class WorkoutBar extends StatelessWidget {
  const WorkoutBar({
    super.key,
    required this.name,
    required this.detail,
    required this.onTap,
  });

  final String name;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MiniBar(
    icon: ForgeIcons.fitnessCenter,
    title: name,
    detail: detail,
    onTap: onTap,
  );
}
