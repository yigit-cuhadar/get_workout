import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_cubit.dart';
import 'consent_cubit.dart';

/// Whether to ask [consent]'s user now: the server says they have not
/// answered, and the app is past onboarding for that same user. The tabs
/// stay up while a new user's profile loads (after signing out, deleting
/// the account or switching accounts), and that user may be on their way
/// to onboarding.
bool consentDue(ConsentState consent, ProfileState profile) =>
    consent.unanswered && consent.uid == profile.uid && profile.pastOnboarding;

/// The analytics consent question as a full-page step: two equal choices,
/// Allow on top. Onboarding asks it after the last question; [ConsentPrompt]
/// asks it of anyone past onboarding who never answered.
class AnalyticsConsentPrompt extends StatelessWidget {
  const AnalyticsConsentPrompt({super.key, required this.onAnswer});

  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PermissionPrompt.consent(
      icon: ForgeIcons.barChart,
      title: l10n.consentTitle,
      message: l10n.consentBody,
      allowLabel: l10n.consentAllow,
      onAllow: () => onAnswer(true),
      declineLabel: l10n.consentDeny,
      onDecline: () => onAnswer(false),
      page: true,
    );
  }
}

/// Asks for analytics consent once [consentDue], as a full page with no
/// way back but an answer. Wraps the tabs and asks only while they are the top route,
/// never over onboarding, the workout, the paywall or a dialog; it
/// asks once they are on top again. Needs [ConsentCubit] and [ProfileCubit]
/// above it.
class ConsentPrompt extends StatefulWidget {
  const ConsentPrompt({super.key, required this.child});

  final Widget child;

  @override
  State<ConsentPrompt> createState() => _ConsentPromptState();
}

class _ConsentPromptState extends State<ConsentPrompt> {
  bool _open = false;

  /// The answer just given, until the cubit's state shows it: saving takes a
  /// moment, and the tabs become the top route again the instant the page
  /// closes, which would ask a second time.
  bool _answered = false;

  /// Also runs when the tabs become, or stop being, the top route.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_askIfDue());
      });
    }
  }

  Future<void> _askIfDue() async {
    if (!mounted || _open || _answered) return;
    final due = consentDue(
      context.read<ConsentCubit>().state,
      context.read<ProfileCubit>().state,
    );
    if (!due) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _open = true;
    final cubit = context.read<ConsentCubit>();
    final consent = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (context) => PopScope(
          canPop: false,
          child: Scaffold(
            body: SafeArea(
              child: AnalyticsConsentPrompt(
                onAnswer: (consent) => Navigator.pop(context, consent),
              ),
            ),
          ),
        ),
      ),
    );
    _open = false;
    if (consent == null) return;
    _answered = true;
    await cubit.answer(consent);
    // Not saved: ask again the next time the tabs come to the front.
    if (cubit.state.failure != null) _answered = false;
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<ConsentCubit, ConsentState>(
        listenWhen: (previous, current) =>
            current.unanswered != previous.unanswered,
        listener: (_, state) {
          if (state.unanswered) {
            unawaited(_askIfDue());
          } else {
            _answered = false;
          }
        },
      ),
      BlocListener<ProfileCubit, ProfileState>(
        listenWhen: (previous, current) =>
            current.uid != previous.uid ||
            current.pastOnboarding != previous.pastOnboarding,
        listener: (_, _) => unawaited(_askIfDue()),
      ),
    ],
    child: widget.child,
  );
}
