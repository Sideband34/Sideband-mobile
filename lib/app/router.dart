import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/widgets.dart';
import '../features/discover/discover_screen.dart';
import '../features/history/history_screen.dart';
import '../features/history/receipt_screen.dart';
import '../features/limits/limits_screen.dart';
import '../features/session/session_screen.dart';

GoRouter buildRouter() => GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              HomeShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (c, s) => const DiscoverScreen()),
            GoRoute(path: '/session', builder: (c, s) => const SessionScreen()),
            GoRoute(path: '/limits', builder: (c, s) => const LimitsScreen()),
            GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
            GoRoute(
                path: '/receipt/:id',
                builder: (c, s) =>
                    ReceiptScreen(sessionId: s.pathParameters['id']!)),
          ],
        ),
      ],
    );

/// Bottom navigation plus a persistent synthetic/testnet banner.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const _tabs = [
    ('/', Icons.radar, 'Discover'),
    ('/session', Icons.bolt_outlined, 'Session'),
    ('/limits', Icons.speed_outlined, 'Limit'),
    ('/history', Icons.receipt_long_outlined, 'History'),
  ];

  @override
  Widget build(BuildContext context) {
    // Receipts are reached from History, so keep that tab selected.
    final tab = location.startsWith('/receipt') ? '/history' : location;
    final idx = _tabs.indexWhere((t) => t.$1 == tab);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(children: [
          BrandMark(size: 30),
          SizedBox(width: 10),
          Text('Sideband'),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                container: true,
                child: const StatusChip(
                  'Pre-release - Testnet / synthetic data only',
                  key: Key('banner'),
                  tone: Tone.warning,
                  icon: Icons.science_outlined,
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx < 0 ? 0 : idx,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.$2), label: t.$3)
        ],
      ),
    );
  }
}
