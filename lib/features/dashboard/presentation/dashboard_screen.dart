import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/contact.dart';
import 'package:formtract/core/models/transaction.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final txAsync = ref.watch(transactionsProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: kBgPage,
      body: txAsync.when(
        loading: () => _buildBody(
          context: context,
          isWide: isWide,
          userName: auth.userName,
          transactions: null,
          contacts: const [],
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txs) => _buildBody(
          context: context,
          isWide: isWide,
          userName: auth.userName,
          transactions: txs,
          contacts: contactsAsync.value ?? [],
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required bool isWide,
    required String userName,
    required List<Transaction>? transactions,
    required List<Contact> contacts,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 28 : 20,
        isWide ? 28 : 20,
        isWide ? 28 : 20,
        isWide ? 28 : 100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GreetingHeader(userName: userName),
          const SizedBox(height: 24),
          _StatsGrid(isWide: isWide, transactions: transactions),
          const SizedBox(height: 24),
          if (isWide)
            _RecentTransactionsTable(
              transactions: transactions?.take(5).toList() ?? [],
              contacts: contacts,
            )
          else
            _RecentTransactionsList(
              transactions: transactions?.take(5).toList() ?? [],
              contacts: contacts,
            ),
        ],
      ),
    );
  }
}

// ── Greeting ──────────────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String userName;
  const _GreetingHeader({required this.userName});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting, $userName',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: kTextSecondary),
        ),
      ],
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final bool isWide;
  final List<Transaction>? transactions;

  const _StatsGrid({required this.isWide, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final txs = transactions;
    final total = txs?.length ?? 0;
    final awaiting = txs
            ?.where((t) => t.status == TransactionStatus.awaitingSignature)
            .length ??
        0;
    final inProgress =
        txs?.where((t) => t.status == TransactionStatus.inProgress).length ??
            0;
    final completed =
        txs?.where((t) => t.status == TransactionStatus.complete).length ?? 0;

    final stats = [
      (
        label: 'Total Transactions',
        value: txs == null ? '—' : '$total',
        icon: Icons.receipt_long,
        color: kBlueAccent,
      ),
      (
        label: 'Awaiting Signature',
        value: txs == null ? '—' : '$awaiting',
        icon: Icons.draw_outlined,
        color: kWarningAmber,
      ),
      (
        label: 'In Progress',
        value: txs == null ? '—' : '$inProgress',
        icon: Icons.pending_outlined,
        color: const Color(0xFF7C3AED),
      ),
      (
        label: 'Completed',
        value: txs == null ? '—' : '$completed',
        icon: Icons.check_circle_outline,
        color: kSuccessGreen,
      ),
    ];

    if (isWide) {
      return Row(
        children: stats
            .asMap()
            .entries
            .map(
              (e) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: e.key < stats.length - 1 ? 16 : 0,
                  ),
                  child: _StatCard(
                    label: e.value.label,
                    value: e.value.value,
                    icon: e.value.icon,
                    color: e.value.color,
                  ),
                ),
              ),
            )
            .toList(),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: stats
          .map(
            (s) => _StatCard(
              label: s.label,
              value: s.value,
              icon: s.icon,
              color: s.color,
            ),
          )
          .toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: kTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _buyerName(Transaction tx, List<Contact> contacts) {
  if (tx.buyerContactId == null || tx.buyerContactId!.isEmpty) return '—';
  try {
    return contacts
        .firstWhere((c) => c.id == tx.buyerContactId)
        .fullName;
  } catch (_) {
    return '—';
  }
}

Color _statusColor(TransactionStatus s) => switch (s) {
      TransactionStatus.draft => kTextSecondary,
      TransactionStatus.inProgress => kBlueAccent,
      TransactionStatus.awaitingSignature => kWarningAmber,
      TransactionStatus.complete => kSuccessGreen,
    };

// ── Recent transactions — desktop table ───────────────────────────────────────

class _RecentTransactionsTable extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Contact> contacts;

  const _RecentTransactionsTable({
    required this.transactions,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Text(
                  'Recent Transactions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/transactions'),
                  child: const Text('View all'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const _TableHeader(),
          const Divider(height: 1),
          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No transactions yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: kTextSecondary),
                ),
              ),
            )
          else
            ...transactions.map(
              (tx) => Column(
                children: [
                  _TableRow(tx: tx, contacts: contacts),
                  const Divider(height: 1),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Buyer')),
          Expanded(flex: 4, child: _HeaderCell('Property Address')),
          Expanded(flex: 2, child: _HeaderCell('Status')),
          Expanded(flex: 2, child: _HeaderCell('Date')),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: kTextSecondary,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final Transaction tx;
  final List<Contact> contacts;

  const _TableRow({required this.tx, required this.contacts});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(tx.status);
    final fmt = DateFormat('MMM d, yyyy');

    return InkWell(
      onTap: () => context.push('/transactions/${tx.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                _buyerName(tx, contacts),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kTextPrimary,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                tx.propertyAddress.isNotEmpty
                    ? tx.fullAddress
                    : 'No address',
                style: const TextStyle(fontSize: 13, color: kTextSecondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tx.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                fmt.format(tx.createdAt),
                style:
                    const TextStyle(fontSize: 13, color: kTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent transactions — mobile list ─────────────────────────────────────────

class _RecentTransactionsList extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Contact> contacts;

  const _RecentTransactionsList({
    required this.transactions,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent Transactions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => context.go('/transactions'),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderColor),
            ),
            child: Center(
              child: Text(
                'No transactions yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: kTextSecondary),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderColor),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transactions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final tx = transactions[i];
                final color = _statusColor(tx.status);
                final buyer = _buyerName(tx, contacts);
                final fmt = DateFormat('MMM d');

                return InkWell(
                  onTap: () => context.push('/transactions/${tx.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tx.propertyAddress.isNotEmpty
                                    ? tx.propertyAddress
                                    : 'No address',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: kTextPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tx.status.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (buyer != '—')
                          Text(
                            buyer,
                            style: const TextStyle(
                              fontSize: 12,
                              color: kTextSecondary,
                            ),
                          ),
                        Text(
                          [
                            if (tx.propertyCity != null) tx.propertyCity!,
                            if (tx.propertyState != null) tx.propertyState!,
                          ].join(', ').isNotEmpty
                              ? [
                                  if (tx.propertyCity != null) tx.propertyCity!,
                                  if (tx.propertyState != null)
                                    tx.propertyState!,
                                ].join(', ')
                              : fmt.format(tx.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
