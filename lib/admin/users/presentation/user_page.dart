import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../admin_router.dart';
import '../../shell/page_header.dart';
import '../domain/admin_user.dart';
import 'user_cubit.dart';
import 'users_cubit.dart';
import 'users_format.dart';
import 'users_page.dart';

/// The actions panel's width.
const _panelWidth = 280.0;

/// A fact's label width.
const _labelWidth = 150.0;

/// From this width the sections sit two by two.
const _twoColumnWidth = 720.0;

/// A user's page: Premium, account, activity and the last device, with
/// every action in one panel on the right.
class UserPage extends StatelessWidget {
  const UserPage({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<UserCubit>(param1: uid)..load(),
    child: const _UserView(),
  );
}

class _UserView extends StatelessWidget {
  const _UserView();

  void _onOutcome(BuildContext context, UserState state) {
    final failure = state.actionFailure;
    if (failure != null) {
      showForgeSnackbar(
        context,
        message: userFailureText(failure),
        error: true,
      );
      return;
    }
    final user = state.user;
    final done = state.done;
    if (done == null || user == null) return;
    showForgeSnackbar(
      context,
      message: switch (done) {
        UserAction.grantPremium => 'Premium granted.',
        UserAction.revokePremium => 'Promotional Premium revoked.',
        UserAction.sendPasswordReset =>
          'Password reset email sent to ${user.email}.',
        UserAction.makeAdmin =>
          'Admin granted. It applies when their sign-in refreshes, '
              'within an hour.',
        UserAction.removeAdmin =>
          'Admin removed. It applies when their sign-in refreshes, '
              'within an hour.',
        UserAction.delete => 'Account deleted.',
      },
    );
    if (done == UserAction.delete) {
      context.read<UsersCubit>().removed(user.uid);
      context.go(AdminRoutes.users);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<UserCubit, UserState>(
        listenWhen: (previous, current) =>
            previous.running != null && current.running == null,
        listener: _onOutcome,
        builder: (context, state) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: usersPageWidth),
            child: ListView(
              padding: const EdgeInsets.all(Gap.lg),
              children: _content(context, state),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, UserState state) {
    final user = state.user;
    final failure = state.failure;
    PageHeader header(String title, String subtitle) => PageHeader(
      title: title,
      subtitle: subtitle,
      back: ('Users', () => context.go(AdminRoutes.users)),
    );
    if (user == null) {
      final loading = header('User', 'Loading');
      if (failure == null) return [loading, const LoadingView()];
      return [
        header('User', "Couldn't load"),
        ErrorView(
          title: 'The user did not load',
          message: userFailureText(failure),
          onRetry: context.read<UserCubit>().load,
          retryLabel: 'Retry',
        ),
      ];
    }
    return [
      header(
        user.email ?? 'Guest, no email',
        'Signed up ${userDateLabel(user.signedUp)} · '
        'last workout ${userDateLabel(user.lastWorkout)}',
      ),
      const SizedBox(height: Gap.md),
      if (failure != null) ...[
        NoticeBanner.line(
          icon: ForgeIcons.info,
          message: 'Showing what loaded before: ${userFailureText(failure)}',
        ),
        const SizedBox(height: Gap.md),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final sections = [
            _PremiumSection(user),
            _AccountSection(user),
            _ActivitySection(user),
            _DevicesSection(user),
          ];
          final twoColumns =
              constraints.maxWidth - _panelWidth - Gap.md >= _twoColumnWidth;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.md,
            children: [
              Expanded(
                child: twoColumns
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Gap.md,
                        children: [
                          Expanded(child: _column([sections[0], sections[2]])),
                          Expanded(child: _column([sections[1], sections[3]])),
                        ],
                      )
                    : _column(sections),
              ),
              SizedBox(
                width: _panelWidth,
                child: _ActionsPanel(user: user, running: state.running),
              ),
            ],
          );
        },
      ),
    ];
  }

  static Widget _column(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Gap.md,
    children: children,
  );
}

/// A label and its value, side by side.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            style: TextStyle(color: ForgeStyle.of(context).colors.inkMuted),
          ),
        ),
        Expanded(child: SelectableText(value)),
        ?trailing,
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.title, this.tag, required this.facts});

  final String title;
  final Widget? tag;
  final List<Widget> facts;

  @override
  Widget build(BuildContext context) {
    return SectionCard.plain(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          if (tag case final tag?)
            Align(alignment: AlignmentDirectional.centerStart, child: tag),
          ...facts,
        ],
      ),
    );
  }
}

class _PremiumSection extends StatelessWidget {
  const _PremiumSection(this.user);

  final UserDetail user;

  @override
  Widget build(BuildContext context) {
    final customer = user.revenueCat;
    final server = user.server;
    // RevenueCat is what the app sees; the server's record when it failed.
    final premium =
        customer?.premium ?? (server?.activeAt(DateTime.now()) ?? false);
    final paid = customer?.storeSubscription;
    final promotional = customer?.promotional;
    String unknown(String none) => switch (user.revenueCatState) {
      RevenueCatState.ok => none,
      RevenueCatState.noCustomer => 'None (not in RevenueCat)',
      RevenueCatState.failed => 'Unknown (RevenueCat did not answer)',
    };
    return _Facts(
      title: 'Premium',
      tag: premium
          ? const ForgeTag('Premium', kind: ForgeTagKind.record)
          : const ForgeTag('Free'),
      facts: [
        _Fact(
          'Store subscription',
          paid == null
              ? unknown('None')
              : [
                  storeLabel(paid.store),
                  codeWords(paid.status),
                  ?paid.productId,
                  if (paid.autoRenewal == 'will_renew')
                    'renews ${userDateLabel(paid.periodEnds)}'
                  else
                    endLabel(paid.periodEnds),
                ].join(' · '),
        ),
        _Fact(
          'Promotional',
          promotional == null
              ? unknown('None')
              : endLabel(promotional.periodEnds),
        ),
        _Fact('Last change', userDateLabel(server?.lastChange)),
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection(this.user);

  final UserDetail user;

  @override
  Widget build(BuildContext context) {
    return _Facts(
      title: 'Account',
      facts: [
        _Fact('Email', user.email ?? '—'),
        _Fact(
          'User ID',
          user.uid,
          trailing: ForgeButton(
            label: 'Copy',
            variant: ForgeButtonVariant.text,
            size: ForgeButtonSize.small,
            leadingIcon: ForgeIcons.contentCopy,
            onPressed: () => Clipboard.setData(ClipboardData(text: user.uid)),
          ),
        ),
        _Fact(
          'Sign-in',
          user.guest ? 'Guest' : user.providers.map(providerLabel).join(', '),
        ),
        _Fact('Signed up', userDateLabel(user.signedUp)),
        _Fact('Admin', user.admin ? 'Yes' : 'No'),
      ],
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection(this.user);

  final UserDetail user;

  @override
  Widget build(BuildContext context) {
    return _Facts(
      title: 'Activity',
      facts: [
        _Fact('Last workout', userDateLabel(user.lastWorkout)),
        _Fact('Workouts', '${user.workouts}'),
        _Fact('Active program', user.activeProgram ?? '—'),
        _Fact('Last opened the app', userDateLabel(user.lastActive)),
      ],
    );
  }
}

class _DevicesSection extends StatelessWidget {
  const _DevicesSection(this.user);

  final UserDetail user;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    Widget row(List<Widget> cells) => Row(
      spacing: Gap.sm,
      children: [for (final cell in cells) Expanded(child: cell)],
    );
    return SectionCard.plain(
      title: 'Devices',
      child: user.devices.isEmpty
          ? const Text('No device has reported yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                row([
                  for (final title in const [
                    'Device',
                    'OS',
                    'App',
                    'Last seen',
                  ])
                    Text(title, style: label),
                ]),
                for (final device in user.devices) ...[
                  const Divider(),
                  row([
                    Text(device.model),
                    Text(
                      '${platformLabel(device.platform)} ${device.osVersion}',
                    ),
                    Text(device.appVersion),
                    Text(userDateLabel(device.lastSeen)),
                  ]),
                ],
              ],
            ),
    );
  }
}

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({required this.user, required this.running});

  final UserDetail user;
  final UserAction? running;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UserCubit>();
    final idle = running == null;
    final canRevoke = user.revenueCat?.promotional != null;
    final canReset = user.email != null && user.hasPassword;
    ForgeButton button(
      String label,
      UserAction action,
      VoidCallback? onPressed, {
      ForgeButtonVariant variant = ForgeButtonVariant.outline,
    }) => ForgeButton(
      label: label,
      variant: variant,
      loading: running == action,
      onPressed: idle ? onPressed : null,
    );
    return SectionCard.plain(
      title: 'Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          button(
            'Grant Premium',
            UserAction.grantPremium,
            () => _grant(context),
            variant: ForgeButtonVariant.primary,
          ),
          button(
            'Revoke Premium',
            UserAction.revokePremium,
            canRevoke ? cubit.revokePremium : null,
          ),
          button(
            'Send password reset email',
            UserAction.sendPasswordReset,
            canReset ? cubit.sendPasswordReset : null,
          ),
          if (user.admin)
            button(
              'Remove admin',
              UserAction.removeAdmin,
              () => cubit.setAdmin(admin: false),
            )
          else
            button(
              'Make admin',
              UserAction.makeAdmin,
              () => cubit.setAdmin(admin: true),
            ),
          const Divider(),
          button(
            'Delete account',
            UserAction.delete,
            () => _delete(context),
            variant: ForgeButtonVariant.danger,
          ),
        ],
      ),
    );
  }

  Future<void> _grant(BuildContext context) async {
    final cubit = context.read<UserCubit>();
    final duration = await showForgeDialog<PremiumDuration>(
      context: context,
      builder: (_) => _GrantDialog(who: user.email ?? user.uid),
    );
    if (duration != null) await cubit.grantPremium(duration);
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<UserCubit>();
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(who: user.email ?? user.uid),
    );
    if (confirmed ?? false) await cubit.delete();
  }
}

/// U3 A: the durations, each with its end date, then Grant Premium.
class _GrantDialog extends StatefulWidget {
  const _GrantDialog({required this.who});

  final String who;

  @override
  State<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends State<_GrantDialog> {
  var _duration = PremiumDuration.month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ForgeDialog(
      title: 'Grant Premium',
      message:
          '${widget.who} gets Premium as a RevenueCat promotional '
          'entitlement. A store subscription is not touched.',
      field: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final duration in PremiumDuration.values)
            ListRow(
              leading: RadioMark(selected: duration == _duration),
              title: durationLabel(duration),
              detail: endLabel(duration.endFrom(now)),
              onTap: () => setState(() => _duration = duration),
            ),
        ],
      ),
      action: ForgeButton(
        label: 'Grant Premium',
        onPressed: () => Navigator.pop(context, _duration),
      ),
      cancel: ForgeButton(
        label: 'Cancel',
        variant: ForgeButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

/// U4 B: deleting is confirmed by ticking "I understand".
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.who});

  final String who;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  var _understood = false;

  @override
  Widget build(BuildContext context) {
    return ForgeDialog(
      title: 'Delete this account?',
      message:
          'This deletes ${widget.who} and all of their data: workouts, '
          'programs, body entries, progress photos and messages. It cannot '
          'be undone. A store subscription is not cancelled; the person '
          'manages it in the store.',
      field: ListRow.check(
        title: 'I understand this cannot be undone',
        checked: _understood,
        onChanged: (value) => setState(() => _understood = value),
      ),
      action: ForgeButton(
        label: 'Delete account',
        variant: ForgeButtonVariant.danger,
        onPressed: _understood ? () => Navigator.pop(context, true) : null,
      ),
      cancel: ForgeButton(
        label: 'Cancel',
        variant: ForgeButtonVariant.text,
        onPressed: () => Navigator.pop(context, false),
      ),
    );
  }
}
