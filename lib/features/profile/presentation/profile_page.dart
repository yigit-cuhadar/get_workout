import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_section.dart';

/// The Profile tab: the account, profile and calculators rows, then the
/// settings.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.select((AuthCubit auth) => auth.user);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProfile)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(
              user == null || user.isAnonymous
                  ? l10n.profileAccountGuest
                  : user.email ?? '',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.account),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.profileDetails),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.profileDetails),
          ),
          ListTile(
            leading: const Icon(Icons.calculate_outlined),
            title: Text(l10n.profileCalculators),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.calculators),
          ),
          const SettingsSection(),
        ],
      ),
    );
  }
}
