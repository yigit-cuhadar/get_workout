import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_review/forge_review.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';

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
