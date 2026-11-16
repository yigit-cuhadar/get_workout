import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/user_profile.dart';
import 'profile_cubit.dart';
import 'profile_form_cubit.dart';
import 'profile_questions.dart';

/// The onboarding answers in two groups, Body and Training, each opening
/// its question to change it.
class ProfileDetailsPage extends StatelessWidget {
  const ProfileDetailsPage({super.key});

  static const body = [
    ProfileField.sex,
    ProfileField.birthYear,
    ProfileField.height,
    ProfileField.weight,
    ProfileField.targetWeight,
  ];
  static const training = [
    ProfileField.goal,
    ProfileField.level,
    ProfileField.daysPerWeek,
    ProfileField.equipment,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProfileCubit>().state;
    final settings = context.select((SettingsCubit c) => c.state.settings);
    final loading = state.status == ProfileStatus.loading;
    List<Widget> rows(List<ProfileField> fields) => [
      for (final (i, field) in fields.indexed)
        loading
            ? ListRow.loading(index: i)
            : ListRow(
                title: l10n.fieldName(field),
                value:
                    l10n.answerText(state.profile, field, settings) ??
                    l10n.profileNotAnswered,
                end: ListRowEnd.chevron,
                onTap: () => context.go(Routes.profileQuestion(field)),
              ),
    ];
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.profileDetails),
      body: state.status == ProfileStatus.unavailable
          ? _Unavailable(l10n)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Gap.md,
                Gap.xs,
                Gap.md,
                Gap.md,
              ),
              children: [
                SettingsColumn(
                  children: [
                    SettingsGroup(
                      title: l10n.profileSectionBody,
                      rows: rows(body),
                    ),
                    SettingsGroup(
                      title: l10n.profileSectionTraining,
                      rows: rows(training),
                    ),
                  ],
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
    final (:uid, :status) = context.select(
      (ProfileCubit cubit) =>
          (uid: cubit.state.uid, status: cubit.state.status),
    );
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.fieldName(field)),
      body: switch (status) {
        ProfileStatus.loading => _QuestionLoading(field),
        ProfileStatus.unavailable => _Unavailable(l10n),
        // A user change starts the answer over from the new user's profile.
        ProfileStatus.loaded => BlocProvider(
          key: ValueKey(uid),
          create: (context) => ProfileFormCubit.edit(
            field: field,
            initial: context.read<ProfileCubit>().state.profile,
          ),
          child: const _QuestionForm(),
        ),
      },
    );
  }
}

/// Shimmering bars where the question's title and line and its answer
/// will be: a number question's value and ruler, or the rows of a choice.
class _QuestionLoading extends StatelessWidget {
  const _QuestionLoading(this.field);

  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    final number = switch (field) {
      ProfileField.birthYear ||
      ProfileField.height ||
      ProfileField.weight ||
      ProfileField.targetWeight => true,
      ProfileField.goal ||
      ProfileField.level ||
      ProfileField.daysPerWeek ||
      ProfileField.equipment ||
      ProfileField.sex => false,
    };
    final radius = ForgeStyle.of(context).radii.md;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                SkeletonBar(widthFactor: 0.7, height: 22),
                SkeletonBar(widthFactor: 0.4, height: 10),
              ],
            ),
            const Spacer(),
            if (number) ...[
              const FractionallySizedBox(
                widthFactor: 0.3,
                child: SkeletonBar(widthFactor: 1, height: 40),
              ),
              const SizedBox(height: Gap.md),
              SkeletonBar(widthFactor: 1, height: 72, radius: radius),
            ] else
              ListRowCard(
                children: [
                  for (var i = 0; i < 3; i++) ListRow.loading(index: i),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => ErrorView(
    title: l10n.profileUnavailable,
    message: l10n.profileUnavailableDetail,
    retryLabel: l10n.retry,
    onRetry: context.read<ProfileCubit>().resume,
  );
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    return BlocListener<ProfileFormCubit, ProfileFormState>(
      listenWhen: (previous, current) =>
          current.status == ProfileFormStatus.submitted &&
          previous.status != current.status,
      // Saved through the app-wide cubit, which reports a rejection on the
      // Profile tab after this page has closed.
      listener: (context, state) {
        context.read<ProfileCubit>().save(state.answers, {
          state.questions.single,
        });
        context.pop();
      },
      child: BlocBuilder<ProfileFormCubit, ProfileFormState>(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ForgeButton(
                      label: l10n.save,
                      size: ForgeButtonSize.large,
                      onPressed: state.canContinue ? cubit.next : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
