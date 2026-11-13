import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

/// Asks for analytics consent once [consentDue]: two equal choices, no
/// dismissing. Wraps the tabs and asks only while they are the top route,
/// never over onboarding, the workout, the paywall or another dialog; it
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
  /// moment, and the tabs become the top route again the instant the dialog
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
    final l10n = AppLocalizations.of(context);
    final consent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.consentTitle),
          content: Text(l10n.consentBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.consentDeny),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.consentAllow),
            ),
          ],
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
