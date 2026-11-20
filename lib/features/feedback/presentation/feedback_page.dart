import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/feedback.dart';
import 'feedback_cubit.dart';

/// Help & feedback: a message, an email for the reply and Send. After
/// sending, a thanks and back.
class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key, required this.source});

  final FeedbackSource source;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<FeedbackCubit>(param1: source),
    child: const _FeedbackView(),
  );
}

class _FeedbackView extends StatefulWidget {
  const _FeedbackView();

  @override
  State<_FeedbackView> createState() => _FeedbackViewState();
}

class _FeedbackViewState extends State<_FeedbackView> {
  late final FeedbackCubit _cubit = context.read<FeedbackCubit>();
  late final _message = TextEditingController(text: _cubit.state.draft.message);
  late final _email = TextEditingController(text: _cubit.state.draft.email);

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<FeedbackCubit, FeedbackState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case FeedbackFormStatus.sent:
            showForgeSnackbar(context, message: l10n.feedbackSent);
            context.pop();
          case FeedbackFormStatus.failed:
            showForgeSnackbar(
              context,
              message: state.failure is NetworkFailure
                  ? l10n.errorNetwork
                  : l10n.feedbackFailed,
              error: true,
            );
          default:
        }
      },
      builder: (context, state) {
        final sending = state.status == FeedbackFormStatus.sending;
        final problems = state.problems;
        return Scaffold(
          appBar: ForgeAppBar(title: l10n.profileFeedback),
          body: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              ForgeTextField(
                label: l10n.feedbackMessage,
                hint: l10n.feedbackMessageHint,
                controller: _message,
                multiline: true,
                maxLength: FeedbackLimits.message,
                enabled: !sending,
                autofocus: true,
                errorText: problems.contains(FeedbackProblem.emptyMessage)
                    ? l10n.feedbackErrorMessage
                    : null,
                onChanged: _cubit.setMessage,
              ),
              const SizedBox(height: Gap.md),
              ForgeTextField(
                label: l10n.feedbackEmail,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                maxLength: FeedbackLimits.email,
                enabled: !sending,
                textInputAction: TextInputAction.done,
                errorText: problems.contains(FeedbackProblem.badEmail)
                    ? l10n.feedbackErrorEmail
                    : null,
                onChanged: _cubit.setEmail,
              ),
              const SizedBox(height: Gap.md),
              Text(
                l10n.feedbackNote,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
              ),
              const SizedBox(height: Gap.md),
              ForgeButton(
                label: l10n.feedbackSend,
                onPressed: sending ? null : _cubit.send,
                loading: sending,
                size: ForgeButtonSize.large,
              ),
            ],
          ),
        );
      },
    );
  }
}
