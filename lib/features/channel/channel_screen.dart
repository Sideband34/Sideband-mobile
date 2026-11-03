import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

import '../../app/providers.dart';
import '../../design_system/widgets.dart';
import '../../domain/channel_state.dart';

/// The payer's funded channel: status, top-up and the payer-initiated close
/// (close_start -> dispute window -> refund). In this build every action runs
/// against a labelled SIMULATION: no Stellar transaction is sent.
class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({super.key});
  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final _amount = TextEditingController(text: '1');
  String? _error;
  bool _busy = false;
  Amount _signed = Amount.zero;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    await ref.read(channelControllerProvider.notifier).refresh();
    final ch = ref.read(channelControllerProvider);
    final s = await ref.read(ledgerProvider).highest(ch.info.channelId);
    if (mounted) setState(() => _signed = Amount.fromStroops(s));
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ChannelActionError catch (e) {
      _error = '${e.code}: ${e.message}';
    } on FormatException catch (e) {
      _error = e.message.isEmpty ? 'Enter a valid amount' : e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmClose() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start closing this channel?'),
        content: const Text(
            'The provider keeps a dispute window to settle the highest voucher '
            'you signed. After it ends you can refund what is left. No new '
            'sessions can use the channel.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('confirm-close'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Start close')),
        ],
      ),
    );
    if (ok == true) {
      await _run(
          () => ref.read(channelControllerProvider.notifier).closeStart());
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  (String, Tone, IconData) _chip(ChannelState s, int now) => switch (s.status) {
        ChannelStatus.open => ('Open', Tone.accent, Icons.lock_open_outlined),
        ChannelStatus.closing => (
            s.refundIn(now) == 0
                ? 'Closing - refund available'
                : 'Closing - dispute window ${s.refundIn(now)}s',
            Tone.warning,
            Icons.hourglass_bottom
          ),
        ChannelStatus.closed => (
            'Closed by provider',
            Tone.neutral,
            Icons.check
          ),
        ChannelStatus.refunded => ('Refunded', Tone.neutral, Icons.undo),
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(channelControllerProvider);
    final now = ref.watch(demoProvider).clock();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (label, tone, icon) = _chip(s, now);
    final left =
        _signed < s.info.deposit ? s.info.deposit - _signed : Amount.zero;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(children: [
          Expanded(
              child:
                  Text('Funded channel', style: theme.textTheme.headlineSmall)),
          if (s.synthetic)
            const StatusChip('Simulated',
                tone: Tone.accent, icon: Icons.science_outlined),
        ]),
        const SizedBox(height: 8),
        StatusChip(label,
            key: const Key('channel-status'), tone: tone, icon: icon),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Deposit'),
                AmountText('${s.info.deposit}', unit: 'TEST-TOKEN'),
                const Divider(height: 28),
                Text('Signed by you so far: $_signed TEST-TOKEN',
                    key: const Key('channel-signed')),
                const SizedBox(height: 4),
                Text('Not yet committed: $left TEST-TOKEN',
                    key: const Key('channel-left')),
                const SizedBox(height: 4),
                Text(
                    s.withdrawn == null
                        ? 'Provider withdrawals: not observed (offline / simulated)'
                        : 'Provider withdrew: ${s.withdrawn} TEST-TOKEN',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                if (s.refunded != null) ...[
                  const SizedBox(height: 4),
                  Text('Refunded to you (simulated): ${s.refunded} TEST-TOKEN',
                      key: const Key('channel-refunded')),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (s.status == ChannelStatus.open) ...[
          TextField(
            key: const Key('topup-field'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Top-up amount (TEST-TOKEN)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('topup-button'),
                onPressed: _busy
                    ? null
                    : () => _run(() => ref
                        .read(channelControllerProvider.notifier)
                        .topUp(Amount.parse(_amount.text.trim()))),
                icon: const Icon(Icons.add),
                label: const Text('Top up'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                key: const Key('close-start-button'),
                onPressed: _busy ? null : _confirmClose,
                child: const Text('Start close'),
              ),
            ),
          ]),
        ],
        if (s.status == ChannelStatus.closing)
          FilledButton.icon(
            key: const Key('refund-button'),
            onPressed: _busy || (s.refundIn(now) ?? 1) > 0
                ? null
                : () => _run(() async {
                      await ref
                          .read(channelControllerProvider.notifier)
                          .refund();
                    }),
            icon: const Icon(Icons.undo),
            label: const Text('Refund remainder'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                key: const Key('channel-error'),
                style: TextStyle(color: cs.error)),
          ),
        const SizedBox(height: 16),
        const Notice(
          icon: Icons.info_outline,
          child: Text(
              'Top-ups and closes are on-chain actions that need internet. '
              'In this preview they are simulated on the device: no Stellar '
              'transaction is sent and no funds move.'),
        ),
      ],
    );
  }
}
