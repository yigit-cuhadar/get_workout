import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/app_mark.dart';
import '../../../core/widgets/onboarding_question.dart';
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
          showForgeSnackbar(
            context,
            message: l10n.profileSaveFailed,
            error: true,
          );
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
          child: OnboardingQuestion(
            step: state.step,
            count: state.questions.length,
            onBack: submitted ? null : cubit.back,
            body: _StepSlide(
              step: state.step,
              child: ProfileQuestion(
                state.question,
                key: ValueKey(state.question),
                onboarding: true,
              ),
            ),
            actionLabel: l10n.onboardingContinue,
            loading: submitted,
            onAction: state.canContinue ? cubit.next : null,
          ),
        );
      },
    );
  }
}

/// The welcome: the mark, the promise, three numbered lines, Get started
/// and, for a guest, I already have an account.
class _Welcome extends StatelessWidget {
  const _Welcome();

  static const double _markTile = 60;
  static const double _markRadius = 15;
  static const double _markSize = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    // Someone signed in to an account (also a guest just linked to one) has
    // nothing to sign in to.
    final guest = context.select(
      (AuthCubit auth) => auth.user?.isAnonymous ?? true,
    );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 60, Gap.lg, Gap.lg),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: _markTile,
                height: _markTile,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(_markRadius),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: colors.onAccent),
                  child: const AppMark(size: _markSize),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(l10n.onboardingWelcomeTitle, style: text.headlineMedium),
            const SizedBox(height: 18),
            Text(
              l10n.onboardingWelcomeSubtitle,
              style: text.bodyLarge!.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: 18),
            BenefitList.numbered([
              l10n.onboardingWelcomeProgram,
              l10n.onboardingWelcomeLog,
              l10n.onboardingWelcomeProgress,
            ]),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.sm,
            children: [
              ForgeButton(
                label: l10n.onboardingGetStarted,
                onPressed: context.read<ProfileFormCubit>().start,
                size: ForgeButtonSize.large,
              ),
              // Nothing is stored before the last question, so a
              // returning user leaves no profile behind on the guest.
              if (guest)
                ForgeButton(
                  label: l10n.accountHaveOne,
                  onPressed: () => context.go(Routes.onboardingSignIn),
                  variant: ForgeButtonVariant.text,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The question of [step]: a later one slides in from the right as the
/// one before leaves to the left, an earlier one (Back) the other way, so
/// each step reads as a new page even where two look alike.
class _StepSlide extends StatefulWidget {
  const _StepSlide({required this.step, required this.child});

  final int step;
  final Widget child;

  @override
  State<_StepSlide> createState() => _StepSlideState();
}

class _StepSlideState extends State<_StepSlide> {
  var _forward = true;

  static const _duration = Duration(milliseconds: 280);

  @override
  void didUpdateWidget(_StepSlide old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) _forward = widget.step > old.step;
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSwitcher(
      duration: _duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(widget.step);
        // The leaving page runs its animation backwards, to this side.
        final side = incoming == _forward ? 1.0 : -1.0;
        return SlideTransition(
          position: Tween(
            begin: Offset(side, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      child: KeyedSubtree(key: ValueKey(widget.step), child: widget.child),
    ),
  );
}
