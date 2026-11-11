import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
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
    final profile = context.select((ProfileCubit c) => c.state.profile);
    final settings = context.select((SettingsCubit c) => c.state.settings);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileDetails)),
      body: ListView(
        children: [
          for (final field in ProfileField.values)
            ListTile(
              title: Text(l10n.fieldName(field)),
              subtitle: Text(
                l10n.answerText(profile, field, settings) ??
                    l10n.profileNotAnswered,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(Routes.profileQuestion(field)),
            ),
        ],
      ),
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
    final profile = context.read<ProfileCubit>().state;
    final uid = profile.uid;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fieldName(field))),
      body: uid == null
          ? const LoadingView()
          : BlocProvider(
              create: (_) => ProfileFormCubit.edit(
                uid: uid,
                field: field,
                initial: profile.profile,
                updateProfile: sl(),
              ),
              child: const _QuestionForm(),
            ),
    );
  }
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    return BlocConsumer<ProfileFormCubit, ProfileFormState>(
      listener: (context, state) {
        if (state.failure != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.profileSaveFailed)));
        } else if (state.status == ProfileFormStatus.submitted) {
          // The answer is already in Firestore's local cache; a server
          // rejection is logged and the stored value reappears.
          context.pop();
        }
      },
      listenWhen: (previous, current) =>
          current.status != previous.status ||
          (current.failure != null && current.failure != previous.failure),
      builder: (context, state) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ProfileQuestion(state.questions.single)),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: ForgeButton(
                label: l10n.save,
                onPressed: state.canContinue ? cubit.next : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
