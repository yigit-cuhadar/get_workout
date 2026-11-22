import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_form_cubit.dart';
import '../../profile/presentation/profile_questions.dart';

/// One profile question of the generator's first page, answered for this
/// program only: Continue pops with the answers, the profile is left as it
/// is.
class GeneratorProfileQuestionPage extends StatelessWidget {
  const GeneratorProfileQuestionPage({
    super.key,
    required this.field,
    required this.initial,
  });

  final ProfileField field;

  /// The generator's profile answers so far.
  final UserProfile initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ForgeAppBar(title: AppLocalizations.of(context).fieldName(field)),
    body: BlocProvider(
      create: (_) => ProfileFormCubit.edit(field: field, initial: initial),
      child: const _Form(),
    ),
  );
}

class _Form extends StatelessWidget {
  const _Form();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    return BlocConsumer<ProfileFormCubit, ProfileFormState>(
      listenWhen: (previous, current) =>
          current.status == ProfileFormStatus.submitted &&
          previous.status != current.status,
      listener: (context, state) => context.pop(state.answers),
      builder: (context, state) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
                child: ProfileQuestion(state.questions.single),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: ForgeButton(
                label: l10n.generatorNext,
                size: ForgeButtonSize.large,
                onPressed: state.canContinue ? cubit.next : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
