import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../account/presentation/privacy_section.dart';
import '../../settings/presentation/settings_section.dart';
import '../../subscription/presentation/premium_card.dart';
import 'profile_cubit.dart';

/// The Profile tab: the account row, the Premium card, the profile and
/// calculators rows, then
/// the settings, privacy and any [debugSection].
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.debugSection});

  /// Developer tools, only ever given in debug builds.
  final Widget? debugSection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.select((AuthCubit auth) => auth.user);
    return BlocListener<ProfileCubit, ProfileState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.profileWriteRejected)));
        context.read<ProfileCubit>().rejectionShown();
      },
      child: Scaffold(
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
            const PremiumCard(),
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
            const PrivacySection(),
            ?debugSection,
          ],
        ),
      ),
    );
  }
}
