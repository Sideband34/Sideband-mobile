import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design_system/widgets.dart';
import '../../domain/manifest.dart';

String _why(ManifestFailure f) => switch (f) {
      ManifestFailure.untrustedProvider => 'Unknown provider key',
      ManifestFailure.wrongNetwork => 'Wrong network',
      ManifestFailure.badSignature => 'Manifest signature invalid',
      ManifestFailure.notYetValid => 'Manifest not yet valid',
      ManifestFailure.staleManifest => 'Manifest expired (stale)',
      ManifestFailure.malformed => 'Manifest malformed',
    };

/// `demo-text-words` -> `Demo text words`.
String _title(Object? serviceId) {
  final s = '$serviceId'.replaceAll(RegExp(r'[-_]+'), ' ').trim();
  return s.isEmpty ? 'Unnamed service' : s[0].toUpperCase() + s.substring(1);
}

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(discoveryProvider);
    final theme = Theme.of(context);
    return listings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Scan failed: $e')),
      data: (items) => items.isEmpty
          ? const Center(child: Text('No nearby services found'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text('Nearby services', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Verified manifests only. You approve every session.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                const Notice(
                  icon: Icons.bluetooth_disabled,
                  child: Text(
                      'Demo mode: a synthetic provider (no Bluetooth / Wi-Fi discovery yet).'),
                ),
                const SizedBox(height: 16),
                for (final l in items) ...[
                  _ServiceCard(
                    listing: l,
                    onConnect: l.trusted
                        ? () async {
                            await ref
                                .read(sessionControllerProvider.notifier)
                                .start(l.service);
                            if (context.mounted) context.go('/session');
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.listing, required this.onConnect});
  final ListingState listing;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final m = listing.service.manifest;
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: s.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.text_fields, color: s.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title(m['serviceId']),
                        style: theme.textTheme.titleMedium),
                    Text('${m['serviceId']}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: s.onSurfaceVariant)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              '${m['pricePerUnit']} ${m['currency']} per ${m['unit']} '
              '- ${m['network']}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              listing.trusted
                  ? const StatusChip('Provider verified',
                      tone: Tone.accent, icon: Icons.verified_outlined)
                  : StatusChip('NOT trusted: ${_why(listing.manifestFailure!)}',
                      tone: Tone.danger, icon: Icons.gpp_bad_outlined),
              StatusChip('Max ${m['maxSessionUnits']} ${m['unit']}s'),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConnect,
                child: const Text('Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
