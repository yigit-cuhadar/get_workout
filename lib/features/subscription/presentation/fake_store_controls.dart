import 'package:flutter/material.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';

import 'paywall_layout.dart';

/// Debug builds on the fake store only: steers the fake and picks the
/// paywall layout for device checks. Developer tooling, so its text is not
/// localized.
class FakeStoreControls extends StatefulWidget {
  const FakeStoreControls(this.store, {super.key, required this.paywallLayout});

  final FakePurchasesRepository store;
  final PaywallLayoutChoice paywallLayout;

  @override
  State<FakeStoreControls> createState() => _FakeStoreControlsState();
}

class _FakeStoreControlsState extends State<FakeStoreControls> {
  static const _failures = <String, Failure?>{
    'Succeed': null,
    'Cancel': PurchaseFailure(PurchaseFailureReason.cancelled),
    'Pending': PurchaseFailure(PurchaseFailureReason.pending),
    'Store unavailable': PurchaseFailure(
      PurchaseFailureReason.storeUnavailable,
    ),
    'No network': NetworkFailure(),
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ListTile(title: Text('Fake store (debug)')),
      ListTile(
        title: const Text('Store calls'),
        trailing: DropdownButton<Failure?>(
          value: widget.store.failure,
          items: [
            for (final MapEntry(:key, :value) in _failures.entries)
              DropdownMenuItem(value: value, child: Text(key)),
          ],
          onChanged: (failure) =>
              setState(() => widget.store.failure = failure),
        ),
      ),
      ListTile(
        title: const Text('Approve pending purchase'),
        onTap: widget.store.approvePending,
      ),
      ListTile(
        title: const Text('Turn off auto-renew'),
        onTap: widget.store.cancelRenewal,
      ),
      ListTile(
        title: const Text('Paywall layout'),
        trailing: DropdownButton<PaywallLayout>(
          value: widget.paywallLayout.layout,
          items: const [
            DropdownMenuItem(
              value: PaywallLayout.list,
              child: Text('A: plan list'),
            ),
            DropdownMenuItem(
              value: PaywallLayout.cards,
              child: Text('B: plan cards'),
            ),
          ],
          onChanged: (layout) {
            if (layout != null) {
              setState(() => widget.paywallLayout.layout = layout);
            }
          },
        ),
      ),
    ],
  );
}
