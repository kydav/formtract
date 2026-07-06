import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  void _seedFromAgent() {
    if (_loaded) return;
    final agent = ref.read(agentProfileProvider).value;
    if (agent == null) return;
    _firstNameCtrl.text = agent.firstName;
    _lastNameCtrl.text = agent.lastName;
    _licenseCtrl.text = agent.licenseNumber ?? '';
    _loaded = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = ref.read(authNotifierProvider);
      final uid = auth.currentUser!.uid;
      await FirebaseFirestore.instance.collection('agents').doc(uid).update({
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        if (_licenseCtrl.text.trim().isNotEmpty)
          'licenseNumber': _licenseCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentAsync = ref.watch(agentProfileProvider);
    final auth = ref.watch(authNotifierProvider);
    final isWide = MediaQuery.of(context).size.width >= 800;

    agentAsync.whenData((_) => _seedFromAgent());

    return Scaffold(
      backgroundColor: kBgPage,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
            child: Row(
              children: [
                if (!isWide)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/dashboard'),
                  ),
                if (!isWide) const SizedBox(width: 4),
                if (isWide)
                  const SizedBox(width: 24),
                Text(
                  'Profile & Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: agentAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (agent) {
                if (agent == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 80 : 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: kBlueAccent,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                agent.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            auth.userEmail,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: kTextSecondary),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Profile form
                        Text(
                          'Profile',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _firstNameCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'First Name',
                                          ),
                                          textCapitalization:
                                              TextCapitalization.words,
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? 'Required'
                                                  : null,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _lastNameCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Last Name',
                                          ),
                                          textCapitalization:
                                              TextCapitalization.words,
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? 'Required'
                                                  : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    initialValue: auth.userEmail,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                    ),
                                    readOnly: true,
                                    style: const TextStyle(
                                        color: kTextSecondary),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _licenseCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'License Number (optional)',
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: _saving ? null : _save,
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 44),
                                      ),
                                      child: _saving
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Save Profile'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Text(
                          'Account',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(
                                  Icons.logout,
                                  color: Colors.red,
                                ),
                                title: const Text(
                                  'Sign Out',
                                  style: TextStyle(color: Colors.red),
                                ),
                                onTap: () =>
                                    ref.read(authNotifierProvider).signOut(),
                              ),
                            ],
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
      ),
    );
  }
}
