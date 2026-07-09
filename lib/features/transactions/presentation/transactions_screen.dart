import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/contact.dart';
import 'package:formtract/core/models/transaction.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionsProvider);
    return Scaffold(
      backgroundColor: kBgPage,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Row(
              children: [
                Text(
                  'Transactions',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showNewTransaction(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Transaction'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
              ],
            ),
          ),
          Expanded(
            child: txAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (txs) => txs.isEmpty
                  ? _EmptyState(onNew: () => _showNewTransaction(context, ref))
                  : _TransactionList(transactions: txs),
            ),
          ),
        ],
      ),
    );
  }

  void _showNewTransaction(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const NewTransactionSheet(),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorderColor),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: kTextSecondary,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Transactions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a transaction to group forms for a deal.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: kTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Transaction'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transaction list ───────────────────────────────────────────────────────────

class _TransactionList extends StatelessWidget {
  final List<Transaction> transactions;
  const _TransactionList({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _TransactionCard(transaction: transactions[i]),
    );
  }
}

class _TransactionCard extends ConsumerWidget {
  final Transaction transaction;
  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (transaction.status) {
      TransactionStatus.draft => kTextSecondary,
      TransactionStatus.inProgress => kBlueAccent,
      TransactionStatus.awaitingSignature => kWarningAmber,
      TransactionStatus.complete => kSuccessGreen,
    };

    return Card(
      child: InkWell(
        onTap: () => context.push('/transactions/${transaction.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kBlueAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.home_outlined,
                  color: kBlueAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.propertyAddress.isNotEmpty
                          ? transaction.propertyAddress
                          : 'No address',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (transaction.propertyCity != null ||
                        transaction.propertyState != null)
                      Text(
                        [
                          transaction.propertyCity,
                          transaction.propertyState,
                        ].where((s) => s?.isNotEmpty ?? false).join(', '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  transaction.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── New transaction sheet ──────────────────────────────────────────────────────

class NewTransactionSheet extends ConsumerStatefulWidget {
  const NewTransactionSheet({super.key});

  @override
  ConsumerState<NewTransactionSheet> createState() =>
      _NewTransactionSheetState();
}

class _NewTransactionSheetState extends ConsumerState<NewTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _countyCtrl = TextEditingController();
  final _sellerCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  Contact? _buyer;
  DateTime? _closingDate;
  bool _saving = false;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _countyCtrl.dispose();
    _sellerCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickClosingDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _closingDate = picked);
  }

  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = ref.read(authNotifierProvider);
      final agent = ref.read(agentProfileProvider).value;
      final uid = auth.currentUser!.uid;
      final now = DateTime.now();
      final price = double.tryParse(_priceCtrl.text.replaceAll(',', '').trim());
      final txId = await createTransaction(
        Transaction(
          id: '',
          agentId: uid,
          boardId: agent?.boardId ?? uid,
          propertyAddress: _addressCtrl.text.trim(),
          propertyCity: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          propertyState: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
          propertyZip: _zipCtrl.text.trim().isEmpty ? null : _zipCtrl.text.trim(),
          propertyCounty: _countyCtrl.text.trim().isEmpty ? null : _countyCtrl.text.trim(),
          sellerName: _sellerCtrl.text.trim().isEmpty ? null : _sellerCtrl.text.trim(),
          purchasePrice: price,
          closingDate: _closingDate,
          buyerContactId: _buyer?.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (!mounted) return;
      Navigator.pop(this.context);
      await this.context.push('/transactions/$txId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBuyer(BuildContext context) async {
    final contacts = ref.read(contactsProvider).value ?? [];
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add contacts first.')),
      );
      return;
    }
    final picked = await showDialog<Contact>(
      context: context,
      builder: (ctx) => _ContactPickerDialog(contacts: contacts),
    );
    if (picked != null) setState(() => _buyer = picked);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final closingLabel = _closingDate != null
        ? '${_closingDate!.month}/${_closingDate!.day}/${_closingDate!.year}'
        : 'Closing Date (optional)';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Transaction', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),

            // ── Property ──
            Text('Property', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Street Address'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(labelText: 'City'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    controller: _stateCtrl,
                    decoration: const InputDecoration(labelText: 'State'),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _zipCtrl,
                    decoration: const InputDecoration(labelText: 'ZIP'),
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _countyCtrl,
              decoration: const InputDecoration(labelText: 'County (optional)'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),

            // ── Deal terms ──
            Text('Deal Terms', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Purchase Price (optional)',
                prefixText: '\$',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _pickClosingDate(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: kBorderColor),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: _closingDate != null ? kTextPrimary : kTextSecondary,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(
                      closingLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _closingDate != null ? kTextPrimary : kTextSecondary,
                      ),
                    ),
                    if (_closingDate != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _closingDate = null),
                        child: const Icon(Icons.close, size: 16, color: kTextSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Parties ──
            Text('Parties', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickBuyer(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: kBorderColor),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        color: _buyer != null ? kTextPrimary : kTextSecondary,
                        size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _buyer?.fullName ?? 'Buyer (optional)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _buyer != null ? kTextPrimary : kTextSecondary,
                        ),
                      ),
                    ),
                    if (_buyer != null)
                      GestureDetector(
                        onTap: () => setState(() => _buyer = null),
                        child: const Icon(Icons.close, size: 16, color: kTextSecondary),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _sellerCtrl,
              decoration: const InputDecoration(labelText: 'Seller Name (optional)'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : () => _save(context),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contact picker dialog ──────────────────────────────────────────────────────

class _ContactPickerDialog extends StatelessWidget {
  final List<Contact> contacts;
  const _ContactPickerDialog({required this.contacts});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Buyer'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final c = contacts[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: kBlueAccent.withValues(alpha: 0.12),
                child: Text(
                  c.initials.isNotEmpty ? c.initials : '?',
                  style: const TextStyle(
                    color: kBlueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              title: Text(c.fullName),
              subtitle: c.email != null ? Text(c.email!) : null,
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
