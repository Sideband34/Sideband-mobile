import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
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
    if (s.stage == SessionStage.idle && s.error == null) {
      return const Center(
          child:
              Text('No active session. Connect to a service from Discover.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (s.stage == SessionStage.active) ...[
          Text('Session active (offline-capable)', key: const Key('stage')),
          Text('Units used: ${s.units}'),
          Text(
              'Committed so far: ${s.committed ?? 0} TEST-TOKEN (signed, not settled)',
              key: const Key('committed')),
          const SizedBox(height: 12),
          TextField(
              key: const Key('text-field'),
              controller: _text,
              decoration: const InputDecoration(
                  labelText: 'Text to convert (billed per word)')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(
              key: const Key('use-button'),
              onPressed: s.busy ? null : () => ctl.use(_text.text),
              child: const Text('Use service'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: const Key('finish-button'),
              onPressed: s.busy
                  ? null
                  : () async {
                      await ctl.finish();
                    },
              child: const Text('End session'),
            ),
          ]),
          if (s.output != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Result: ${s.output}', key: const Key('output'))),
        ],
        if (s.stage == SessionStage.closed)
          const Text('Session closed', key: Key('stage')),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(s.error!,
                key: const Key('error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
