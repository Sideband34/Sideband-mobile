import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    ('/session', Icons.bolt, 'Session'),
    ('/limits', Icons.speed, 'Limit'),
    ('/history', Icons.receipt_long, 'History'),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = _tabs.indexWhere((t) => t.$1 == location);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Sideband'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(24),
            child: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('Pre-release - Testnet / synthetic data only',
                  key: Key('banner')),
            ),
          )),
      body: child,
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
