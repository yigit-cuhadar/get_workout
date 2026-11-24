import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../account/presentation/account_auth_page.dart';
import '../../account/presentation/auth_strings.dart';
import '../../account/presentation/privacy_section.dart';
import '../../notifications/presentation/reminder_settings_group.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../settings/presentation/settings_section.dart';
import '../../steps/presentation/connected_apps_group.dart';
import '../../steps/presentation/health_access_cubit.dart';
import '../../subscription/presentation/premium_card.dart';
import '../../subscription/presentation/premium_trial_cubit.dart';
import 'profile_cubit.dart';

/// The Profile tab: the account header, the Premium card, the profile,
/// then every setting in groups and the [devTools].
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.devTools = const []});

  /// Developer tools, never given in release builds.
  final List<Widget> devTools;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<ProfileCubit, ProfileState>(
          listenWhen: (_, current) => current.writeRejected,
          listener: (context, _) {
            showForgeSnackbar(
              context,
              message: l10n.profileWriteRejected,
              error: true,
            );
            context.read<ProfileCubit>().rejectionShown();
          },
        ),
        BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (previous, current) =>
              current.failure != null && current.failure != previous.failure,
          listener: (context, _) => showForgeSnackbar(
            context,
            message: l10n.settingsSaveFailed,
            error: true,
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => sl<HealthAccessCubit>()),
          // Read, and so loaded, only while the user is free.
          BlocProvider(create: (_) => sl<PremiumTrialCubit>()..load()),
        ],
        child: Scaffold(
          appBar: ForgeAppBar(title: l10n.tabProfile),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            children: [
              SettingsColumn(
                children: [
                  const _Header(),
                  const PremiumCard(),
                  SettingsGroup(
                    title: l10n.profileYou,
                    rows: [
                      ListRow(
                        title: l10n.profileDetails,
                        detail: l10n.profileDetailsDetail,
                        end: ListRowEnd.chevron,
                        onTap: () => context.go(Routes.profileDetails),
                      ),
                    ],
                  ),
                  const WorkoutSettingsGroups(),
                  const ReminderSettingsGroup(),
                  const ConnectedAppsGroup(),
                  const AppearanceGroup(),
                  const PrivacySection(),
                  ...devTools,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The account: a guest is asked to keep their workouts in an account (the
/// guest account sheet); a named user shows the name over the email and
/// opens Account; without a name the email stands in for it. An Apple
/// relay address is never shown: a named user shows the name alone, an
/// unnamed one is "Apple account" with a person icon.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.select((AuthCubit auth) => auth.user);
    void open() => context.go(Routes.account);
    if (user == null || user.isAnonymous) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, 0),
        child: ProfileHeader.guest(
          name: l10n.profileGuestName,
          detail: l10n.profileGuestDetail,
          onTap: () => showLinkAccountSheet(
            context,
            title: l10n.guestSheetTitle,
            message: l10n.guestSheetMessage,
            // The email form links the guest in create mode.
            onUseEmail: () => context.push(Routes.accountAuth),
            strings: localizedAuthStrings(l10n),
            providers: socialProviders,
          ),
        ),
      );
    }
    final name = user.displayName?.trim() ?? '';
    // Apple shares no name and, unless the user lets it, only a relay
    // address that means nothing to them.
    final email = isAppleRelay(user.email) ? '' : user.email ?? '';
    if (name.isEmpty &&
        email.isEmpty &&
        user.signInMethods.contains(SignInMethod.apple)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, 0),
        child: ProfileHeader.guest(
          name: l10n.profileAppleName,
          detail: l10n.profileAppleDetail,
          onTap: open,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, 0),
      child: ProfileHeader(
        initials: initialsOf(name.isEmpty ? email : name),
        name: name.isEmpty ? email : name,
        detail: name.isEmpty ? null : email,
        onTap: open,
      ),
    );
  }
}

/// Whether [email] is an address Sign in with Apple made up to hide the
/// user's own.
@visibleForTesting
bool isAppleRelay(String? email) =>
    email?.toLowerCase().endsWith('@privaterelay.appleid.com') ?? false;

/// Up to two letters: the first of the first two words of [name], or of
/// an email its first letter.
@visibleForTesting
String initialsOf(String name) {
  if (name.contains('@')) {
    return name.characters.take(1).toString().toUpperCase();
  }
  return name
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.characters.first)
      .join()
      .toUpperCase();
}
