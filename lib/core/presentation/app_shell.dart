import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/agent.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/router/router.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:formtract/features/contacts/presentation/contacts_screen.dart';
import 'package:formtract/features/transactions/presentation/transactions_screen.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const AppShell({required this.location, required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    if (isWide) {
      return _DesktopShell(location: location, child: child);
    }
    return _MobileShell(location: location, child: child);
  }
}

// ─── Nav item definitions ───────────────────────────────────────────────────

class _NavDef {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavDef({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

const _navItems = [
  _NavDef(
    path: '/dashboard',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Dashboard',
  ),
  _NavDef(
    path: '/transactions',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    label: 'Transactions',
  ),
  _NavDef(
    path: '/templates',
    icon: Icons.description_outlined,
    activeIcon: Icons.description,
    label: 'Templates',
  ),
  _NavDef(
    path: '/contacts',
    icon: Icons.people_outline_rounded,
    activeIcon: Icons.people_rounded,
    label: 'Contacts',
  ),
];

// ─── Desktop shell ───────────────────────────────────────────────────────────

class _DesktopShell extends StatelessWidget {
  final String location;
  final Widget child;

  const _DesktopShell({required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: Row(
        children: [
          _Sidebar(location: location),
          Expanded(
            child: Column(children: [Expanded(child: child)]),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  final String location;

  const _Sidebar({required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);

    return Container(
      width: 240,
      color: kNavyDark,
      child: SafeArea(
        child: Column(
          children: [
            // Logo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kBlueAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'F',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'formtract',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            // Nav items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _navItems
                    .map(
                      (item) => _SidebarNavItem(
                        item: item,
                        active: location.startsWith(item.path),
                        onTap: () => ref.read(routerProvider).go(item.path),
                      ),
                    )
                    .toList(),
              ),
            ),

            // Settings + user footer
            const Divider(color: Colors.white12, height: 1),
            _SidebarNavItem(
              item: const _NavDef(
                path: '/settings',
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Settings',
              ),
              active: location.startsWith('/settings'),
              onTap: () => ref.read(routerProvider).go('/settings'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: kBlueAccent,
                    child: Text(
                      auth.userInitials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          auth.userEmail,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.logout,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    onPressed: () => ref.read(authNotifierProvider).signOut(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Sign out',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final _NavDef item;
  final bool active;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        // Use kNavyDark (not transparent) so the Material always occupies a
        // real hit-test area on Flutter web. Inactive items look identical to
        // the sidebar background; active items get the white tint via InkWell.
        color: active ? kNavyLight : kNavyDark,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  active ? item.activeIcon : item.icon,
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (active) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: kBlueAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Mobile shell ─────────────────────────────────────────────────────────────

class _MobileShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const _MobileShell({required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final agent = ref.watch(agentProfileProvider).value;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavyDark,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: kBlueAccent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Text(
                  'F',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'formtract',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _ProfileDrawer(auth: auth, agent: agent),
      body: child,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _FloatingBottomNav(location: location),
        ),
      ),
    );
  }

  static void showQuickCreate(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Create',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kBlueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: kBlueAccent,
                    size: 20,
                  ),
                ),
                title: const Text('New Transaction'),
                subtitle: const Text('Start a deal with a property address'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (_) => const NewTransactionSheet(),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kSuccessGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_add_outlined,
                    color: kSuccessGreen,
                    size: 20,
                  ),
                ),
                title: const Text('Add Contact'),
                subtitle: const Text('Save a buyer, seller, or client'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (_) => const AddContactSheet(),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kWarningAmber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: kWarningAmber,
                    size: 20,
                  ),
                ),
                title: const Text('Fill a Form'),
                subtitle: const Text(
                  'Fill a standalone form without a transaction',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go('/templates');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  final String location;

  const _FloatingBottomNav({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: kNavyDark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Home',
            active: location.startsWith('/dashboard'),
            onTap: () => context.go('/dashboard'),
          ),
          _BottomItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long,
            label: 'Transactions',
            active: location.startsWith('/transactions'),
            onTap: () => context.go('/transactions'),
          ),
          GestureDetector(
            onTap: () => _MobileShell.showQuickCreate(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kBlueAccent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: kBlueAccent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
          ),
          _BottomItem(
            icon: Icons.people_outline_rounded,
            activeIcon: Icons.people_rounded,
            label: 'Contacts',
            active: location.startsWith('/contacts'),
            onTap: () => context.go('/contacts'),
          ),
          _BottomItem(
            icon: Icons.description_outlined,
            activeIcon: Icons.description,
            label: 'Templates',
            active: location.startsWith('/templates'),
            onTap: () => context.go('/templates'),
          ),
        ],
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : Colors.white.withValues(alpha: 0.5);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile drawer (mobile end drawer) ───────────────────────────────────────

class _ProfileDrawer extends ConsumerWidget {
  final AuthNotifier auth;
  final Agent? agent;

  const _ProfileDrawer({required this.auth, required this.agent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = agent?.initials ?? auth.userInitials;
    final name = agent?.fullName.isNotEmpty == true
        ? agent!.fullName
        : auth.userName;

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: kBlueAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.userEmail,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kTextSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),
            const SizedBox(height: 8),

            // Settings
            ListTile(
              leading: const Icon(Icons.settings_outlined, size: 22),
              title: const Text('Profile & Settings'),
              onTap: () {
                Navigator.pop(context);
                context.go('/settings');
              },
            ),

            const Spacer(),
            const Divider(height: 1),

            // Sign out
            ListTile(
              leading: const Icon(Icons.logout, size: 22, color: Colors.red),
              title: const Text(
                'Sign Out',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => auth.signOut(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
