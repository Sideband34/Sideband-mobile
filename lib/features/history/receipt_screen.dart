import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../session/session_view.dart';

class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(historyProvider);
    return h.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final matches = items.where((r) => r.sessionId == sessionId);
        if (matches.isEmpty) {
          return const Center(child: Text('Receipt not found'));
        }
        return SingleChildScrollView(
          child: SessionView(
              receipt: matches.first, now: ref.watch(demoProvider).clock()),
        );
      },
    );
  }
}
