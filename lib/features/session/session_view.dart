import 'package:flutter/material.dart';

import '../../domain/receipt.dart';

/// Pure presentation of a session summary. No payment logic lives here.
class SessionView extends StatelessWidget {
  const SessionView({super.key, required this.receipt, required this.now});

  final Receipt receipt;
  final int now;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return Semantics(
      container: true,
      label: 'Session receipt',
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Session ${r.sessionId}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Units used: ${r.units}'),
              Text('Network: Stellar Testnet (test funds only)'),
              const SizedBox(height: 8),
              Text(r.statusLabel, key: const Key('status')),
              if (!r.isFinal) ...[
                const SizedBox(height: 4),
                Text(
                  'This is a signed commitment, not a completed payment.',
                  key: const Key('disclosure'),
                ),
                Text(r.refundHint(now), key: const Key('refund')),
              ],
              Text('Reason closed: ${r.closeReason}'),
            ],
          ),
        ),
      ),
    );
  }
}
