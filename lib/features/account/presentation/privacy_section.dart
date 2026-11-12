import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/legal_links.dart';
import '../../../core/open_link.dart';
import '../../../l10n/app_localizations.dart';
import 'consent_cubit.dart';

/// The analytics consent switch and the privacy policy. Needs
/// [ConsentCubit] above it.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<ConsentCubit, ConsentState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (context, _) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.privacySaveFailed))),
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(dense: true, title: Text(l10n.privacyHeader)),
          SwitchListTile(
            title: Text(l10n.privacyShareUsage),
            subtitle: Text(l10n.privacyShareUsageInfo),
            value: state.consent ?? false,
            onChanged: state.loaded
                ? context.read<ConsentCubit>().answer
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicy),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openPolicy(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openPolicy(BuildContext context) async {
    final failed = AppLocalizations.of(context).linkOpenFailed;
    final messenger = ScaffoldMessenger.of(context);
    if (await openLink(LegalLinks.privacy)) return;
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
