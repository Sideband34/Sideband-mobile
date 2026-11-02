import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design_system/widgets.dart';
import 'session_view.dart';

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});
  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  final _text = TextEditingController(text: 'hello brave new world');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionControllerProvider);
    final ctl = ref.read(sessionControllerProvider.notifier);
    final demo = ref.watch(demoProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (s.stage == SessionStage.idle && s.error == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('No active session. Connect to a service from Discover.',
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (s.stage == SessionStage.active) ...[
          Row(children: [
            Expanded(
              child: Text('Session active (offline-capable)',
                  key: const Key('stage'), style: theme.textTheme.titleMedium),
            ),
            // Honest transport label: the demo provider is in-memory.
            const StatusChip('Synthetic provider',
                tone: Tone.accent, icon: Icons.science_outlined),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Committed so far'),
                  AmountText('${s.committed ?? 0}', unit: 'TEST-TOKEN'),
                  const SizedBox(height: 4),
                  Text(
                      'Committed so far: ${s.committed ?? 0} TEST-TOKEN (signed, not settled)',
                      key: const Key('committed'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  const Divider(height: 28),
                  Row(children: [
                    Icon(Icons.straighten,
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('Units used: ${s.units}'),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
              key: const Key('text-field'),
              controller: _text,
              decoration: const InputDecoration(
                  labelText: 'Text to convert (billed per word)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('use-button'),
                onPressed: s.busy ? null : () => ctl.use(_text.text),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Use service'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                key: const Key('finish-button'),
                onPressed: s.busy
                    ? null
                    : () async {
                        await ctl.finish();
                      },
                child: const Text('End session'),
              ),
            ),
          ]),
          if (s.output != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14)),
                child: Text('Result: ${s.output}',
                    key: const Key('output'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        ],
        if (s.stage == SessionStage.closed)
          Text('Session closed',
              key: const Key('stage'), style: theme.textTheme.titleMedium),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline, color: cs.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.error!,
                    key: const Key('error'), style: TextStyle(color: cs.error)),
              ),
            ]),
          ),
        if (s.receipt != null)
          SessionView(receipt: s.receipt!, now: demo.clock()),
        if (s.stage == SessionStage.closed)
          TextButton(
              onPressed: () {
                ctl.reset();
                context.go('/');
              },
              child: const Text('Back to Discover')),
      ],
    );
  }
}
