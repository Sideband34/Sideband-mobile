import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

import '../../app/providers.dart';

/// Per-session spending limit. The session never signs a cumulative amount
/// above this, whatever the provider requests.
class LimitsScreen extends ConsumerStatefulWidget {
  const LimitsScreen({super.key});
  @override
  ConsumerState<LimitsScreen> createState() => _LimitsScreenState();
}

class _LimitsScreenState extends ConsumerState<LimitsScreen> {
  late final TextEditingController _c =
      TextEditingController(text: ref.read(spendLimitProvider).toString());
  String? _error;

  void _save() {
    try {
      final a = Amount.parse(_c.text.trim());
      if (a == Amount.zero) {
        throw const FormatException('Limit must be above zero');
      }
      ref.read(spendLimitProvider.notifier).set(a);
      setState(() => _error = null);
    } on FormatException catch (e) {
      setState(() => _error = e.message.isEmpty
          ? 'Enter a valid amount (up to 7 decimals)'
          : e.message);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(spendLimitProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Per-session spending limit',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Current: $current TEST-TOKEN', key: const Key('current-limit')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('limit-field'),
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Limit (TEST-TOKEN)', errorText: _error),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Save limit')),
          const SizedBox(height: 16),
          const Text(
              'Applies to the next session you start. Commitments are never signed above it.'),
        ],
      ),
    );
  }
}
