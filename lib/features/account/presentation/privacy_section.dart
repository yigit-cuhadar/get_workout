import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../app/legal_links.dart';
import '../../../core/open_link.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import 'consent_cubit.dart';

/// The Privacy group: the analytics consent switch and the privacy policy.
/// Needs [ConsentCubit] above it.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<ConsentCubit, ConsentState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (context, _) => showForgeSnackbar(
        context,
        message: l10n.privacySaveFailed,
        error: true,
      ),
      builder: (context, state) => SettingsGroup(
        title: l10n.privacyHeader,
        rows: [
          ListRow(
            title: l10n.privacyShareUsage,
            detail: l10n.privacyShareUsageInfo,
            trailing: ForgeSwitch(
              value: state.consent ?? false,
              onChanged: state.loaded
                  ? context.read<ConsentCubit>().answer
                  : null,
            ),
          ),
          ListRow(
            title: l10n.privacyPolicy,
            end: ListRowEnd.external,
            onTap: () => _openPolicy(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openPolicy(BuildContext context) async {
    final failed = AppLocalizations.of(context).linkOpenFailed;
    if (await openLink(LegalLinks.privacy)) return;
    if (context.mounted) {
      showForgeSnackbar(context, message: failed, error: true);
    }
  }
}
