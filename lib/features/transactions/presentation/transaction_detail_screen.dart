import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/contact.dart';
import 'package:formtract/core/models/filled_form.dart'
    show FilledForm, FilledFormStatus;
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/models/transaction.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final String txId;
  const TransactionDetailScreen({required this.txId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionByIdProvider(txId));

    return txAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (tx) {
        if (tx == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Transaction')),
            body: const Center(child: Text('Transaction not found.')),
          );
        }
        return _TransactionDetailView(tx: tx);
      },
    );
  }
}

// ── Main view ─────────────────────────────────────────────────────────────────

class _TransactionDetailView extends ConsumerWidget {
  final Transaction tx;
  const _TransactionDetailView({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filledAsync = ref.watch(filledFormsProvider(tx.id));

    // Watch the buyer contact if one is set.
    final buyerAsync = tx.buyerContactId != null
        ? ref.watch(contactByIdProvider(tx.buyerContactId!))
        : null;

    return Scaffold(
      backgroundColor: kBgPage,
      body: Column(
        children: [
          // ── Top bar ───────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/transactions'),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.propertyAddress.isNotEmpty
                            ? tx.propertyAddress
                            : 'New Transaction',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (tx.propertyCity != null || tx.propertyState != null)
                        Text(
                          [
                            tx.propertyCity,
                            tx.propertyState,
                          ].where((s) => s?.isNotEmpty ?? false).join(', '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: kTextSecondary),
                        ),
                    ],
                  ),
                ),
                _StatusChip(tx: tx),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Transaction'),
                          content: const Text(
                            'This will permanently delete the transaction and all its forms.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await deleteTransaction(tx.id);
                        if (context.mounted) context.go('/transactions');
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Buyer card
                _BuyerSection(
                  tx: tx,
                  buyer: buyerAsync?.value,
                  onPick: () => _pickBuyer(context, ref),
                ),
                const SizedBox(height: 16),

                // Forms section header
                Row(
                  children: [
                    Text(
                      'Forms',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _addForm(context, ref),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Form'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                filledAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Text('Error: $e'),
                  data: (forms) => forms.isEmpty
                      ? _EmptyForms(onAdd: () => _addForm(context, ref))
                      : _FormsList(forms: forms, tx: tx),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBuyer(BuildContext context, WidgetRef ref) async {
    final contacts = ref.read(contactsProvider).value ?? [];
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add contacts first on the Contacts screen.'),
        ),
      );
      return;
    }
    final picked = await showDialog<Contact?>(
      context: context,
      builder: (ctx) => _ContactPickerDialog(
        contacts: contacts,
        currentId: tx.buyerContactId,
      ),
    );
    if (picked != null) {
      await updateTransactionContact(tx.id, buyerContactId: picked.id);
    } else if (picked == null && context.mounted && tx.buyerContactId != null) {
      // null sentinel from "Remove" button
    }
  }

  Future<void> _addForm(BuildContext context, WidgetRef ref) async {
    final templates = ref.read(formTemplatesProvider(tx.boardId)).value ?? [];
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No templates. Add one in Templates.')),
      );
      return;
    }
    final template = await showDialog<FormTemplate>(
      context: context,
      builder: (ctx) => _TemplatePicker(templates: templates),
    );
    if (template != null && context.mounted) {
      await context.push('/fill/${tx.id}/${template.id}');
    }
  }
}

// ── Status chip with tap-to-change ───────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final Transaction tx;
  const _StatusChip({required this.tx});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (tx.status) {
      TransactionStatus.draft => kTextSecondary,
      TransactionStatus.inProgress => kBlueAccent,
      TransactionStatus.awaitingSignature => kWarningAmber,
      TransactionStatus.complete => kSuccessGreen,
    };

    return GestureDetector(
      onTap: () => _changeStatus(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tx.status.label,
              style: TextStyle(
                fontSize: 11,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: statusColor),
          ],
        ),
      ),
    );
  }

  void _changeStatus(BuildContext context) {
    showDialog<TransactionStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set Status'),
        children: TransactionStatus.values
            .map(
              (s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s),
                child: Text(s.label),
              ),
            )
            .toList(),
      ),
    ).then((picked) {
      if (picked != null) {
        unawaited(updateTransactionStatus(tx.id, picked));
      }
    });
  }
}

// ── Buyer section ─────────────────────────────────────────────────────────────

class _BuyerSection extends ConsumerWidget {
  final Transaction tx;
  final Contact? buyer;
  final VoidCallback onPick;

  const _BuyerSection({
    required this.tx,
    required this.buyer,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kBlueAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: buyer != null
                  ? Center(
                      child: Text(
                        buyer!.initials.isNotEmpty ? buyer!.initials : '?',
                        style: const TextStyle(
                          color: kBlueAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.person_outline,
                      color: kBlueAccent,
                      size: 20,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buyer != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          buyer!.fullName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (buyer!.email != null)
                          Text(
                            buyer!.email!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: kTextSecondary),
                          ),
                      ],
                    )
                  : Text(
                      'No buyer linked',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: kTextSecondary),
                    ),
            ),
            TextButton(
              onPressed: onPick,
              child: Text(buyer != null ? 'Change' : 'Link Buyer'),
            ),
            if (buyer != null)
              TextButton(
                onPressed: () =>
                    updateTransactionContact(tx.id, buyerContactId: ''),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty forms state ─────────────────────────────────────────────────────────

class _EmptyForms extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyForms({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 40,
              color: kTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No forms yet',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: kTextSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Form'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Forms list ────────────────────────────────────────────────────────────────

class _FormsList extends StatelessWidget {
  final List<FilledForm> forms;
  final Transaction tx;
  const _FormsList({required this.forms, required this.tx});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: forms.map((f) => _FormCard(form: f, tx: tx)).toList(),
    );
  }
}

class _FormCard extends StatelessWidget {
  final FilledForm form;
  final Transaction tx;
  const _FormCard({required this.form, required this.tx});

  @override
  Widget build(BuildContext context) {
    final isDone = form.status == FilledFormStatus.complete;
    final statusColor = isDone ? kSuccessGreen : kBlueAccent;
    final fmt = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.push('/fill/${tx.id}/${form.templateId}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isDone ? Icons.check_circle_outline : Icons.edit_document,
                  color: statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form.templateName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${isDone ? 'Completed' : 'Draft'} · ${fmt.format(form.updatedAt)}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: kTextSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Template picker dialog ────────────────────────────────────────────────────

class _TemplatePicker extends StatelessWidget {
  final List<FormTemplate> templates;
  const _TemplatePicker({required this.templates});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Form'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: templates.length,
          itemBuilder: (context, i) {
            final t = templates[i];
            return ListTile(
              leading: const Icon(Icons.description_outlined, size: 20),
              title: Text(t.name),
              subtitle: (t.description?.isNotEmpty ?? false)
                  ? Text(t.description!)
                  : null,
              onTap: () => Navigator.pop(context, t),
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

// ── Contact picker dialog (also used for buyer change) ───────────────────────

class _ContactPickerDialog extends StatelessWidget {
  final List<Contact> contacts;
  final String? currentId;
  const _ContactPickerDialog({required this.contacts, this.currentId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link Buyer'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final c = contacts[i];
            return ListTile(
              selected: c.id == currentId,
              leading: CircleAvatar(
                backgroundColor: kBlueAccent.withValues(alpha: 0.12),
                radius: 18,
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
