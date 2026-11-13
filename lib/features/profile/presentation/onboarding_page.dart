import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/question_page.dart';

import '../../../l10n/app_localizations.dart';
import 'profile_cubit.dart';
import 'profile_form_cubit.dart';
import 'profile_questions.dart';

/// A welcome, then the first-run questions, one per screen. The router
/// shows it until the profile records completion, and moves on by itself
/// once it does; this page never navigates away.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The form belongs to whoever is signed in: a user change starts it over
    // for the new user, once their profile has loaded.
    final uid = context.select(
      (ProfileCubit cubit) =>
          cubit.state.status == ProfileStatus.loaded ? cubit.state.uid : null,
    );
    if (uid == null) return const Scaffold(body: LoadingView());
    return BlocProvider(
      key: ValueKey(uid),
      create: (context) => ProfileFormCubit.onboarding(
        uid: uid,
        initial: context.read<ProfileCubit>().state.profile,
        completeOnboarding: sl(),
      ),
      child: const _OnboardingView(),
    );
  }
}

class _OnboardingView extends StatelessWidget {
  const _OnboardingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    return BlocConsumer<ProfileFormCubit, ProfileFormState>(
      listenWhen: (previous, current) =>
          current.status != previous.status ||
          (current.failure != null && current.failure != previous.failure),
      listener: (context, state) {
        if (state.failure != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.profileSaveFailed)));
        } else if (state.status == ProfileFormStatus.submitted) {
          // If the profile stream is down, the completion would never show
          // up and the user would stay here.
          context.read<ProfileCubit>().resume();
        }
      },
      builder: (context, state) {
        if (state.welcome) return const _Welcome();
        final submitted = state.status == ProfileFormStatus.submitted;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.back();
          },
          child: QuestionScaffold(
            step: state.step,
            count: state.questions.length,
            progress: l10n.questionProgress(
              state.step + 1,
              state.questions.length,
            ),
            onBack: submitted ? null : cubit.back,
            body: ProfileQuestion(
              state.question,
              key: ValueKey(state.question),
            ),
            action: ForgeButton(
              label: l10n.onboardingNext,
              loading: submitted,
              onPressed: state.canContinue ? cubit.next : null,
            ),
          ),
        );
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Someone signed in to an account (also a guest just linked to one) has
    // nothing to sign in to.
    final guest = context.select(
      (AuthCubit auth) => auth.user?.isAnonymous ?? true,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.md),
                children: [
                  const SizedBox(height: Gap.xl),
                  Text(
                    l10n.onboardingWelcomeTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: Gap.md),
                  for (final (icon, text) in [
                    (Icons.calendar_month, l10n.onboardingWelcomeProgram),
                    (Icons.check, l10n.onboardingWelcomeLog),
                    (Icons.show_chart, l10n.onboardingWelcomeProgress),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon),
                      title: Text(text),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ForgeButton(
                    label: l10n.onboardingGetStarted,
                    onPressed: context.read<ProfileFormCubit>().start,
                  ),
                  // Nothing is stored before the last question, so a
                  // returning user leaves no profile behind on the guest.
                  if (guest)
                    TextButton(
                      onPressed: () => context.go(Routes.onboardingSignIn),
                      child: Text(l10n.accountHaveOne),
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
