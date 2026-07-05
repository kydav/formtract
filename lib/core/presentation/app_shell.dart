import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/theme/app_theme.dart';

class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const AppShell({
    required this.location,
    required this.child,
    super.key,
  });

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

String _titleForLocation(String location) {
  if (location.startsWith('/transactions')) return 'Transactions';
  if (location.startsWith('/templates')) return 'Templates';
  if (location.startsWith('/contacts')) return 'Contacts';
  return 'Dashboard';
}

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
            child: Column(
              children: [
                _DesktopTopBar(location: location),
                Expanded(child: child),
              ],
            ),
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
                        onTap: () => context.go(item.path),
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
              onTap: () {},
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
                            color: Colors.white.withOpacity(0.4),
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
                      color: Colors.white.withOpacity(0.4),
                    ),
                    onPressed: () => ref.read(authNotifierProvider).logout(),
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
        color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withOpacity(0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  active ? item.activeIcon : item.icon,
                  color: active
                      ? Colors.white
                      : Colors.white.withOpacity(0.55),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : Colors.white.withOpacity(0.55),
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

// ─── Desktop top bar ─────────────────────────────────────────────────────────

class _DesktopTopBar extends ConsumerWidget {
  final String location;

  const _DesktopTopBar({required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kBorderColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(
            _titleForLocation(location),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 17, color: kTextPrimary),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Form'),
          ),
          const SizedBox(width: 16),
          CircleAvatar(
            radius: 18,
            backgroundColor: kBlueAccent,
            child: Text(
              auth.userInitials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile shell ─────────────────────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  final String location;
  final Widget child;

  const _MobileShell({required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      extendBody: true,
      body: child,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _FloatingBottomNav(location: location),
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
            color: Colors.black.withOpacity(0.22),
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
            onTap: () {},
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kBlueAccent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: kBlueAccent.withOpacity(0.4),
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
    final color = active ? Colors.white : Colors.white.withOpacity(0.5);
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
