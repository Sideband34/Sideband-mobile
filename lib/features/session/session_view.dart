import 'package:flutter/material.dart';

import '../../design_system/widgets.dart';
import '../../domain/receipt.dart';

/// Pure presentation of a session summary. No payment logic lives here.
class SessionView extends StatelessWidget {
  const SessionView({super.key, required this.receipt, required this.now});

  final Receipt receipt;
  final int now;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted =
        theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);
    return Semantics(
      container: true,
      label: 'Session receipt',
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Session ${r.sessionId}',
                      style: theme.textTheme.titleMedium),
                ),
                Icon(
                    r.isFinal
                        ? Icons.verified_outlined
                        : Icons.hourglass_top_rounded,
                    color: r.isFinal ? cs.primary : cs.onSurfaceVariant),
              ]),
              const SizedBox(height: 12),
              Text(r.statusLabel,
                  key: const Key('status'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Divider(height: 28),
              Text('Units used: ${r.units}', style: muted),
              Text('Network: Stellar Testnet (test funds only)', style: muted),
              Text('Reason closed: ${r.closeReason}', style: muted),
              if (!r.isFinal) ...[
                const SizedBox(height: 14),
                Notice(
                  icon: Icons.info_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This is a signed commitment, not a completed payment.',
                        key: const Key('disclosure'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(r.refundHint(now), key: const Key('refund')),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
