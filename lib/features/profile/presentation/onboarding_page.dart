import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/user_profile.dart';
import 'profile_cubit.dart';
import 'profile_form_cubit.dart';
import 'profile_questions.dart';

/// The first-run questions, one per screen, then a summary. The router shows
/// it until the profile records completion, and moves on by itself once it
/// does; this page never navigates away.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileCubit>().state;
    final uid = profile.uid;
    // The router opens this page only for a signed-in user's loaded profile.
    if (uid == null) return const Scaffold(body: LoadingView());
    return BlocProvider(
      create: (_) => ProfileFormCubit.onboarding(
        uid: uid,
        initial: profile.profile,
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
        final question = state.question;
        final count = state.questions.length;
        final submitted = state.status == ProfileFormStatus.submitted;
        return PopScope(
          canPop: state.step == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.back();
          },
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: state.step > 0
                  ? BackButton(onPressed: submitted ? null : cubit.back)
                  : null,
              title: question == null
                  ? null
                  : Text(l10n.onboardingProgress(state.step + 1, count)),
              actions: [
                if (question != null)
                  TextButton(
                    onPressed: submitted ? null : cubit.skip,
                    child: Text(l10n.onboardingSkip),
                  ),
              ],
            ),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: state.step / count),
                  Expanded(
                    child: question == null
                        ? _Summary(state.answers)
                        : ProfileQuestion(question, key: ValueKey(question)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: ForgeButton(
                      label: question == null
                          ? l10n.onboardingStart
                          : l10n.onboardingNext,
                      loading: submitted,
                      onPressed: state.canContinue ? cubit.next : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The answers to confirm before starting.
class _Summary extends StatelessWidget {
  const _Summary(this.answers);

  final UserProfile answers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = context.select((SettingsCubit c) => c.state.settings);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text(l10n.onboardingSummaryTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Gap.sm),
        Text(l10n.onboardingSummaryInfo, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Gap.md),
        for (final field in ProfileField.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldName(field)),
            trailing: Text(
              l10n.answerText(answers, field, settings) ??
                  l10n.profileNotAnswered,
            ),
          ),
      ],
    );
  }
}
