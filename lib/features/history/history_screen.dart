import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design_system/widgets.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(historyProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return h.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load history: $e')),
      data: (items) => items.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined,
                    size: 48, color: cs.onSurfaceVariant),
                const SizedBox(height: 12),
                const Text('No sessions yet'),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text('History', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Receipts stay "committed" until Stellar confirms them.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                for (final r in items) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: Key('history-${r.sessionId}'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: Icon(
                          r.isFinal
                              ? Icons.verified_outlined
                              : Icons.hourglass_top_rounded,
                          color: r.isFinal ? cs.primary : cs.onSurfaceVariant),
                      title: Text('${r.units} units - ${r.statusLabel}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusChip(
                              'Session ${r.sessionId} - ${r.closeReason}'),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/receipt/${r.sessionId}'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}
