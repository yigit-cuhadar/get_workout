import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../account/presentation/consent_cubit.dart';
import '../../account/presentation/consent_prompt.dart';
import '../../notifications/domain/reminder_settings_changes.dart';
import '../../notifications/presentation/notifications_cubit.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../steps/domain/steps.dart';
import '../../steps/presentation/health_access_cubit.dart';
import '../domain/user_profile.dart';

/// After the last onboarding question: analytics consent unless the user
/// already answered, the workout reminder unless the device already lets
/// the app notify, then the health store unless access is granted or there
/// is none, then [next] (the program suggestion). A refused permission
/// moves on silently; a consent that did not save is asked again in the
/// tabs.
class OnboardingPermissionsPage extends StatelessWidget {
  const OnboardingPermissionsPage({super.key, required this.next});

  final Widget next;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<HealthAccessCubit>(),
    child: _Steps(next: next),
  );
}

enum _Step { consent, reminders, health, done }

class _Steps extends StatefulWidget {
  const _Steps({required this.next});

  final Widget next;

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> {
  var _step = _Step.consent;

  /// Taken when the step is reached: an answer read later is asked in the
  /// tabs instead.
  late final bool _asksConsent = context.read<ConsentCubit>().state.unanswered;

  /// Told while the reminder step shows, so the health step rarely waits.
  late final Future<void> _healthKnown;

  @override
  void initState() {
    super.initState();
    _healthKnown = context.read<HealthAccessCubit>().load();
  }

  void _go(_Step step) {
    if (mounted) setState(() => _step = step);
  }

  void _answerConsent(bool consent) {
    unawaited(context.read<ConsentCubit>().answer(consent));
    _go(_Step.reminders);
  }

  Future<void> _turnOnReminders() async {
    final settings = context.read<SettingsCubit>();
    if (await context.read<NotificationsCubit>().allow()) {
      await settings.update(
        settings.state.settings.withWorkoutReminder(enabled: true),
      );
    }
    _go(_Step.health);
  }

  /// Asks where the system still can; where it will not ask again (iOS
  /// once asked, Android refused for good), the store's settings.
  Future<void> _connectHealth() async {
    final health = context.read<HealthAccessCubit>();
    switch (health.state) {
      case StepsAccess.undetermined:
        await health.openSettings();
      case StepsAccess.denied:
        await health.allow();
        if (health.state == StepsAccess.denied) await health.openSettings();
      case _:
        await health.allow();
    }
    _go(_Step.done);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifying = context.select(
      (NotificationsCubit cubit) => cubit.state.allowed == true,
    );
    final step = switch (_step) {
      _Step.consent when !_asksConsent =>
        notifying ? _Step.health : _Step.reminders,
      // Allowed already: nothing to ask, so the reminder stays as it is.
      _Step.reminders when notifying => _Step.health,
      final step => step,
    };
    switch (step) {
      case _Step.done:
        return widget.next;
      case _Step.consent:
        return _StepPage(AnalyticsConsentPrompt(onAnswer: _answerConsent));
      case _Step.reminders:
        return _StepPage(
          PermissionPrompt.ask(
            icon: ForgeIcons.notifications,
            title: l10n.onboardingRemindersTitle,
            message: l10n.onboardingRemindersBody,
            allowLabel: l10n.onboardingRemindersAllow,
            onAllow: _turnOnReminders,
            skipLabel: l10n.onboardingRemindersNotNow,
            onSkip: () => _go(_Step.health),
            page: true,
          ),
        );
      case _Step.health:
        return FutureBuilder(
          future: _healthKnown,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _StepPage(LoadingView());
            }
            // Asked wherever a store exists and steps may not be read.
            if (!_asksHealth(context.read<HealthAccessCubit>().state)) {
              return widget.next;
            }
            final store = Theme.of(context).platform == TargetPlatform.iOS
                ? l10n.stepsStoreApple
                : l10n.stepsStoreGoogle;
            return _StepPage(
              PermissionPrompt.ask(
                icon: ForgeIcons.directionsWalk,
                title: l10n.onboardingHealthTitle,
                message: l10n.onboardingHealthBody(store),
                allowLabel: l10n.onboardingHealthAllow(store),
                onAllow: _connectHealth,
                skipLabel: l10n.onboardingHealthSkip,
                onSkip: () => _go(_Step.done),
                page: true,
              ),
            );
          },
        );
    }
  }
}

bool _asksHealth(StepsAccess? access) => switch (access) {
  StepsAccess.explain || StepsAccess.denied || StepsAccess.undetermined => true,
  StepsAccess.granted ||
  StepsAccess.unsupported ||
  StepsAccess.notInstalled ||
  null => false,
};

/// A step after the questions: their progress, full, over the [prompt].
class _StepPage extends StatelessWidget {
  const _StepPage(this.prompt);

  final Widget prompt;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, Gap.lg, 20, 0),
            child: StepProgress(
              count: ProfileField.values.length,
              current: ProfileField.values.length,
            ),
          ),
          Expanded(child: prompt),
        ],
      ),
    ),
  );
}
