import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(historyProvider);
    return h.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load history: $e')),
      data: (items) => items.isEmpty
          ? const Center(child: Text('No sessions yet'))
          : ListView(
              children: [
                for (final r in items)
                  ListTile(
                    key: Key('history-${r.sessionId}'),
                    title: Text('${r.units} units - ${r.statusLabel}'),
                    subtitle: Text('Session ${r.sessionId} - ${r.closeReason}'),
                    onTap: () => context.go('/receipt/${r.sessionId}'),
                  ),
              ],
            ),
    );
  }
}
