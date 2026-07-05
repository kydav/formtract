import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/theme/app_theme.dart';

// Mock data — replaced with Firestore queries in Phase 3
const _mockTransactions = [
  {
    'buyer': 'Sarah Johnson',
    'address': '1420 Oak Ridge Dr, Cedar City UT',
    'status': 'Signed',
    'date': 'Jul 3, 2026',
    'form': 'BC-60 Buyer Agreement',
  },
  {
    'buyer': 'Mark & Lisa Chen',
    'address': '892 Canyon View Rd, St George UT',
    'status': 'Awaiting',
    'date': 'Jul 2, 2026',
    'form': 'BC-60 Buyer Agreement',
  },
  {
    'buyer': 'David Hernandez',
    'address': '305 Pinecrest Blvd, Parowan UT',
    'status': 'In Progress',
    'date': 'Jul 1, 2026',
    'form': 'Listing Agreement',
  },
  {
    'buyer': 'Amy & Tom Walsh',
    'address': '78 Juniper Ln, Enoch UT',
    'status': 'Signed',
    'date': 'Jun 29, 2026',
    'form': 'BC-60 Buyer Agreement',
  },
  {
    'buyer': 'Rachel Torres',
    'address': '2210 Valley Ridge Ct, Cedar City UT',
    'status': 'Awaiting',
    'date': 'Jun 28, 2026',
    'form': 'Purchase Agreement',
  },
];

const _stats = [
  {'label': 'Total Transactions', 'value': '12', 'icon': Icons.receipt_long, 'color': kBlueAccent},
  {'label': 'Awaiting Signature', 'value': '5', 'icon': Icons.draw_outlined, 'color': kWarningAmber},
  {'label': 'In Progress', 'value': '3', 'icon': Icons.pending_outlined, 'color': Color(0xFF7C3AED)},
  {'label': 'Completed', 'value': '28', 'icon': Icons.check_circle_outline, 'color': kSuccessGreen},
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: kBgPage,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isWide ? 28 : 20,
          isWide ? 28 : 20,
          isWide ? 28 : 20,
          isWide ? 28 : 100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GreetingHeader(userName: auth.userName),
            const SizedBox(height: 24),
            _StatsGrid(isWide: isWide),
            const SizedBox(height: 24),
            if (isWide)
              _RecentTransactionsTable()
            else
              _RecentTransactionsList(),
          ],
        ),
      ),
    );
  }
}

// ─── Greeting ─────────────────────────────────────────────────────────────────

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

// ─── Stats grid ───────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final bool isWide;

  const _StatsGrid({required this.isWide});

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      return Row(
        children: _stats
            .map(
              (s) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _StatCard(
                    label: s['label'] as String,
                    value: s['value'] as String,
                    icon: s['icon'] as IconData,
                    color: s['color'] as Color,
                  ),
                ),
              ),
            )
            .toList()
          ..last = Expanded(
            child: _StatCard(
              label: _stats.last['label'] as String,
              value: _stats.last['value'] as String,
              icon: _stats.last['icon'] as IconData,
              color: _stats.last['color'] as Color,
            ),
          ),
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: _stats
          .map(
            (s) => _StatCard(
              label: s['label'] as String,
              value: s['value'] as String,
              icon: s['icon'] as IconData,
              color: s['color'] as Color,
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
              color: color.withOpacity(0.1),
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

// ─── Recent transactions — desktop table ──────────────────────────────────────

class _RecentTransactionsTable extends StatelessWidget {
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
                  onPressed: () {},
                  child: const Text('View all'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _TableHeader(),
          const Divider(height: 1),
          ..._mockTransactions.map(
            (tx) => Column(
              children: [
                _TableRow(tx: tx),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: const [
          Expanded(flex: 3, child: _HeaderCell('Buyer / Party')),
          Expanded(flex: 4, child: _HeaderCell('Property Address')),
          Expanded(flex: 3, child: _HeaderCell('Form')),
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
  final Map<String, String> tx;

  const _TableRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              tx['buyer']!,
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
              tx['address']!,
              style: const TextStyle(fontSize: 13, color: kTextSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              tx['form']!,
              style: const TextStyle(fontSize: 13, color: kTextSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: _StatusBadge(tx['status']!),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tx['date']!,
              style: const TextStyle(fontSize: 13, color: kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent transactions — mobile list ────────────────────────────────────────

class _RecentTransactionsList extends StatelessWidget {
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
            TextButton(onPressed: () {}, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderColor),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _mockTransactions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tx = _mockTransactions[index];
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tx['buyer']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: kTextPrimary,
                            ),
                          ),
                        ),
                        _StatusBadge(tx['status']!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tx['address']!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tx['form']} · ${tx['date']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Signed' => (
          kSuccessGreen.withOpacity(0.12),
          kSuccessGreen,
        ),
      'Awaiting' => (
          kWarningAmber.withOpacity(0.12),
          kWarningAmber,
        ),
      _ => (
          kBlueAccent.withOpacity(0.12),
          kBlueAccent,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
