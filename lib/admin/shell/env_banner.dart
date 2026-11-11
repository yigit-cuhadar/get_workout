import 'package:flutter/material.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

/// Names the Firebase project the panel writes to, above every page. Prod
/// gets the error colours: edits there reach users at their next sync.
class EnvBanner extends StatelessWidget {
  const EnvBanner({super.key, required this.env, required this.projectId});

  final AppEnv env;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = env.isProd
        ? (scheme.error, scheme.onError)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    final text = env.isProd
        ? 'PRODUCTION · $projectId · edits reach every user at their next sync'
        : 'DEV · $projectId';
    return Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Row(
            children: [
              Icon(
                env.isProd ? Icons.warning_amber : Icons.science_outlined,
                color: foreground,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
