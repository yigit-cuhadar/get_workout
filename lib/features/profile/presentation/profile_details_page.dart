import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/user_profile.dart';
import 'profile_cubit.dart';
import 'profile_form_cubit.dart';
import 'profile_questions.dart';

/// The onboarding answers, each opening its question to change it.
class ProfileDetailsPage extends StatelessWidget {
  const ProfileDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProfileCubit>().state;
    final settings = context.select((SettingsCubit c) => c.state.settings);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileDetails)),
      body: switch (state.status) {
        ProfileStatus.loading => const LoadingView(),
        ProfileStatus.unavailable => _Unavailable(l10n),
        ProfileStatus.loaded => ListView(
          children: [
            for (final field in ProfileField.values)
              ListTile(
                title: Text(l10n.fieldName(field)),
                subtitle: Text(
                  l10n.answerText(state.profile, field, settings) ??
                      l10n.profileNotAnswered,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(Routes.profileQuestion(field)),
              ),
          ],
        ),
      },
    );
  }
}

/// One question of the profile; saving stores only its answer.
class ProfileQuestionPage extends StatelessWidget {
  const ProfileQuestionPage(this.field, {super.key});

  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (:uid, :status) = context.select(
      (ProfileCubit cubit) =>
          (uid: cubit.state.uid, status: cubit.state.status),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fieldName(field))),
      body: switch (status) {
        ProfileStatus.loading => const LoadingView(),
        ProfileStatus.unavailable => _Unavailable(l10n),
        // A user change starts the answer over from the new user's profile.
        ProfileStatus.loaded => BlocProvider(
          key: ValueKey(uid),
          create: (context) => ProfileFormCubit.edit(
            field: field,
            initial: context.read<ProfileCubit>().state.profile,
          ),
          child: const _QuestionForm(),
        ),
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => ErrorView(
    message: l10n.profileUnavailable,
    retryLabel: l10n.retry,
    onRetry: context.read<ProfileCubit>().resume,
  );
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    // Only a stored answer is worth clearing.
    final stored = context.select((ProfileCubit c) => c.state.profile);
    return BlocListener<ProfileFormCubit, ProfileFormState>(
      listenWhen: (previous, current) =>
          current.status == ProfileFormStatus.submitted &&
          previous.status != current.status,
      // Saved through the app-wide cubit, which reports a rejection on the
      // Profile tab after this page has closed.
      listener: (context, state) {
        context.read<ProfileCubit>().save(state.answers, {
          state.questions.single,
        });
        context.pop();
      },
      child: BlocBuilder<ProfileFormCubit, ProfileFormState>(
        builder: (context, state) => SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ProfileQuestion(state.questions.single)),
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ForgeButton(
                      label: l10n.save,
                      onPressed: state.canContinue ? cubit.next : null,
                    ),
                    if (state.canClear && stored.answered(state.question))
                      TextButton(
                        onPressed: cubit.clear,
                        child: Text(l10n.profileClearAnswer),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
