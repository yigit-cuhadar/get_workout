import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import 'consent_cubit.dart';

/// Asks for analytics consent once the server says the signed-in user has
/// not answered: two equal choices, no dismissing. Wraps the tabs and asks
/// only while they are the top route, never over onboarding, the workout,
/// the paywall or another dialog; it asks once they are on top again.
/// Needs [ConsentCubit] above it.
class ConsentPrompt extends StatefulWidget {
  const ConsentPrompt({super.key, required this.child});

  final Widget child;

  @override
  State<ConsentPrompt> createState() => _ConsentPromptState();
}

class _ConsentPromptState extends State<ConsentPrompt> {
  bool _open = false;

  /// Also runs when the tabs become, or stop being, the top route.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_askIfUnanswered(context.read<ConsentCubit>().state));
      });
    }
  }

  Future<void> _askIfUnanswered(ConsentState state) async {
    if (!mounted || _open || !state.unanswered) return;
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
    if (consent != null) unawaited(cubit.answer(consent));
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<ConsentCubit, ConsentState>(
        listenWhen: (previous, current) =>
            current.unanswered && !previous.unanswered,
        listener: (_, state) => unawaited(_askIfUnanswered(state)),
        child: widget.child,
      );
}
