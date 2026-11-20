import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_review/forge_review.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

/// Whether the tab page at [context] is what the user sees: its tab is in
/// front at [location], and nothing covers the tabs (a paywall, the
/// workout, the consent page, a dialog or a sheet).
bool tabInFront(BuildContext context, String location) {
  final shell = ModalRoute.of(Navigator.of(context).context);
  return (ModalRoute.of(context)?.isCurrent ?? false) &&
      (shell?.isCurrent ?? true) &&
      openLocations(GoRouter.of(context).routerDelegate.currentConfiguration)
              .lastOrNull ==
          location;
}

/// Asks whether the user enjoys the app: "Yes!" opens the store's review
/// prompt, "Not really" then "Write to us" pushes [feedbackRoute]. Needs a
/// [ReviewPromptCubit] above [context].
Future<void> askForReview(BuildContext context, String feedbackRoute) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<ReviewPromptCubit>();
  final answer = await showReviewPrompt(
    context,
    ReviewPromptStrings(
      title: l10n.reviewTitle,
      message: l10n.reviewMessage,
      yes: l10n.reviewYes,
      no: l10n.reviewNo,
      close: l10n.close,
      thanksTitle: l10n.reviewThanksTitle,
      thanksMessage: l10n.reviewThanksMessage,
      writeToUs: l10n.reviewWriteToUs,
    ),
  );
  if (!context.mounted) return;
  switch (answer) {
    case ReviewAnswer.liked:
      await cubit.rate();
    case ReviewAnswer.writeToUs:
      await context.push(feedbackRoute);
    case null:
  }
}
