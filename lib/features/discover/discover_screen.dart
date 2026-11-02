import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/manifest.dart';

String _why(ManifestFailure f) => switch (f) {
      ManifestFailure.untrustedProvider => 'Unknown provider key',
      ManifestFailure.wrongNetwork => 'Wrong network',
      ManifestFailure.badSignature => 'Manifest signature invalid',
      ManifestFailure.notYetValid => 'Manifest not yet valid',
      ManifestFailure.staleManifest => 'Manifest expired (stale)',
      ManifestFailure.malformed => 'Manifest malformed',
    };

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(discoveryProvider);
    return listings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Scan failed: $e')),
      data: (items) => items.isEmpty
          ? const Center(child: Text('No nearby services found'))
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Demo mode: a synthetic provider (no Bluetooth / Wi-Fi discovery yet).'),
                ),
                for (final l in items)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text('${l.service.manifest['serviceId']}'),
                      subtitle: Text(
                        '${l.service.manifest['pricePerUnit']} ${l.service.manifest['currency']} per ${l.service.manifest['unit']} '
                        '- ${l.service.manifest['network']}\n'
                        '${l.trusted ? 'Provider verified' : 'NOT trusted: ${_why(l.manifestFailure!)}'}',
                      ),
                      isThreeLine: true,
                      trailing: FilledButton(
                        onPressed: l.trusted
                            ? () async {
                                await ref
                                    .read(sessionControllerProvider.notifier)
                                    .start(l.service);
                                if (context.mounted) context.go('/session');
                              }
                            : null,
                        child: const Text('Connect'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
