import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/presentation/app_shell.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/features/auth/presentation/login_screen.dart';
import 'package:formtract/features/contacts/presentation/contacts_screen.dart';
import 'package:formtract/features/dashboard/presentation/dashboard_screen.dart';
import 'package:formtract/features/forms/presentation/form_filler_screen.dart';
import 'package:formtract/features/templates/presentation/templates_screen.dart';
import 'package:formtract/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:formtract/features/transactions/presentation/transactions_screen.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.read(authNotifierProvider);
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authNotifier,
    redirect: (BuildContext context, GoRouterState state) {
      final loggedIn = authNotifier.isLoggedIn;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      // Full-screen form filler — outside the shell so it has no nav chrome.
      // Path: /fill/:txId/:templateId   (txId == 'new' for testing from templates)
      GoRoute(
        path: '/fill/:txId/:templateId',
        builder: (context, state) => FormFillerScreen(
          txId: state.pathParameters['txId']!,
          templateId: state.pathParameters['templateId']!,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: '/transactions',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TransactionsScreen()),
          ),
          GoRoute(
            path: '/transactions/:txId',
            pageBuilder: (context, state) => NoTransitionPage(
              child: TransactionDetailScreen(
                txId: state.pathParameters['txId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/templates',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TemplatesScreen()),
          ),
          GoRoute(
            path: '/contacts',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ContactsScreen()),
          ),
        ],
      ),
    ],
  );
});
