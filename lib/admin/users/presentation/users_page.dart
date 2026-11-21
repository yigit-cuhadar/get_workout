import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../admin_router.dart';
import '../domain/admin_user.dart';
import 'users_cubit.dart';
import 'users_format.dart';

/// The widest the page grows on a desktop screen.
const usersPageWidth = 1280.0;

/// The search's width.
const _searchWidth = 520.0;

/// The columns' shares of a row: email, user ID, Premium, signed up, last
/// workout, platform, Open.
const _columns = [16, 10, 5, 6, 6, 4, 3];

/// Users: find one by email or user ID, over the latest sign-ups with Load
/// more. The [UsersCubit] comes from the section's route.
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: usersPageWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: const [
              _FindSection(),
              SizedBox(height: Gap.md),
              _LatestSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindSection extends StatefulWidget {
  const _FindSection();

  @override
  State<_FindSection> createState() => _FindSectionState();
}

class _FindSectionState extends State<_FindSection> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final uid = await context.read<UsersCubit>().find(_query.text);
    if (uid != null && mounted) context.go(AdminRoutes.user(uid));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UsersCubit>().state;
    final failure = state.findFailure;
    return SectionCard.plain(
      title: 'Find a user',
      note: 'Exact email or user ID.',
      child: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: _searchWidth,
            child: ForgeTextField(
              label: 'Email or user ID',
              controller: _query,
              textInputAction: TextInputAction.search,
              errorText: failure == null ? null : userFailureText(failure),
              onSubmitted: (_) => _find(),
            ),
          ),
          ForgeButton(label: 'Find', loading: state.finding, onPressed: _find),
        ],
      ),
    );
  }
}

class _LatestSection extends StatelessWidget {
  const _LatestSection();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsersCubit>();
    final state = context.watch<UsersCubit>().state;
    final users = state.users;
    final failure = state.failure;
    if (users == null) {
      if (failure == null) return const LoadingView();
      return ErrorView(
        title: 'The sign-ups did not load',
        message: userFailureText(failure),
        onRetry: cubit.load,
        retryLabel: 'Retry',
      );
    }
    final muted = TextStyle(color: ForgeStyle.of(context).colors.inkMuted);
    return SectionCard.plain(
      title: 'Recent sign-ups',
      note: 'Newest first',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (users.isEmpty) const Text('Nobody has signed up yet.'),
          if (users.isNotEmpty) ...[
            _Row(
              cells: [
                for (final title in const [
                  'Email',
                  'User ID',
                  'Premium',
                  'Signed up',
                  'Last workout',
                  'Platform',
                  '',
                ])
                  Text(title, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            for (final user in users) ...[
              const Divider(),
              _Row(
                cells: [
                  Text(
                    user.email ?? 'Guest, no email',
                    style: user.email == null ? muted : null,
                  ),
                  SelectableText(user.uid, maxLines: 1),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _PremiumTag(user),
                  ),
                  Text(userDateLabel(user.signedUp)),
                  Text(userDateLabel(user.lastWorkout)),
                  Text(platformLabel(user.platform)),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ForgeButton(
                      label: 'Open',
                      variant: ForgeButtonVariant.text,
                      size: ForgeButtonSize.small,
                      onPressed: () => context.go(AdminRoutes.user(user.uid)),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (failure != null) ...[
            const SizedBox(height: Gap.sm),
            Text(userFailureText(failure)),
          ],
          if (state.next != null || state.loadingMore) ...[
            const SizedBox(height: Gap.md),
            Center(
              child: ForgeButton(
                label: 'Load more',
                variant: ForgeButtonVariant.outline,
                loading: state.loadingMore,
                onPressed: cubit.loadMore,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        spacing: Gap.sm,
        children: [
          for (final (i, cell) in cells.indexed)
            Expanded(flex: _columns[i], child: cell),
        ],
      ),
    );
  }
}

class _PremiumTag extends StatelessWidget {
  const _PremiumTag(this.user);

  final UserRow user;

  @override
  Widget build(BuildContext context) => switch (user) {
    UserRow(premium: true) => const ForgeTag(
      'Premium',
      kind: ForgeTagKind.record,
    ),
    UserRow(guest: true) => const ForgeTag('Guest'),
    _ => const ForgeTag('Free'),
  };
}
