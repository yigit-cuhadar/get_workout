import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../access/presentation/access_cubit.dart';
import '../admin_router.dart';

/// Every signed-in page: the left menu of [adminSections] beside the page.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.location, required this.child});

  /// The path shown, whose section the menu marks.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Menu(location: location),
      const VerticalDivider(width: 1),
      Expanded(child: child),
    ],
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.location});

  final String location;

  /// The menu's width on the S1 board.
  static const _width = 232.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final access = context.watch<AccessCubit>().state;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.sm),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Gap.sm),
                    child: Text(
                      'GetWorkout Admin',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  for (final (i, section) in adminSections.indexed) ...[
                    if (section.group case final group?
                        when i == 0 || adminSections[i - 1].group != group)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: Gap.sm,
                          top: Gap.sm,
                        ),
                        child: SectionLabel(group),
                      ),
                    _Entry(section: section, selected: section.opens(location)),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (access case SignedIn(:final user))
                    Text(
                      user.email ?? user.id,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  TextButton(
                    onPressed: context.read<AccessCubit>().signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.section, required this.selected});

  final AdminSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(section.label),
      trailing: section.count,
      selected: selected,
      selectedColor: scheme.onSecondaryContainer,
      selectedTileColor: scheme.secondaryContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Gap.sm)),
      ),
      // On a subpage (an editor) the marked entry leads back to its list.
      onTap: () => context.go(section.path),
    );
  }
}
