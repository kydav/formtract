import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/services/template_service.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentAsync = ref.watch(agentProfileProvider);
    return agentAsync.when(
      loading: () =>
          const _Shell(child: Center(child: CircularProgressIndicator())),
      error: (e, _) => _Shell(child: Center(child: Text('Error: $e'))),
      data: (agent) => agent == null
          ? const _Shell(child: SizedBox.shrink())
          : _TemplatesBody(boardId: agent.boardId),
    );
  }
}

// ── Scaffold wrapper shared by loading/error states ───────────────────────────

class _Shell extends StatelessWidget {
  final Widget child;
  const _Shell({required this.child});

  @override
  Widget build(BuildContext context) {
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
                  'Templates',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _TemplatesBody extends ConsumerStatefulWidget {
  final String boardId;
  const _TemplatesBody({required this.boardId});

  @override
  ConsumerState<_TemplatesBody> createState() => _TemplatesBodyState();
}

class _TemplatesBodyState extends ConsumerState<_TemplatesBody> {
  String _query = '';
  String? _selectedCategory;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showUploadSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _UploadPdfSheet(boardId: widget.boardId),
    );
  }

  List<FormTemplate> _filter(List<FormTemplate> templates) {
    var result = templates;
    if (_selectedCategory != null) {
      result = result.where((t) => t.category == _selectedCategory).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where(
            (t) =>
                t.name.toLowerCase().contains(q) ||
                (t.category?.toLowerCase().contains(q) ?? false) ||
                (t.description?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(formTemplatesProvider(widget.boardId));

    return Scaffold(
      backgroundColor: kBgPage,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                  child: Row(
                    children: [
                      Text(
                        'Templates',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _showUploadSheet(context),
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('Upload PDF'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      ),
                    ],
                  ),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search templates…',
                      prefixIcon:
                          const Icon(Icons.search, size: 20, color: kTextSecondary),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: templatesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (templates) {
                if (templates.isEmpty) {
                  return _EmptyState(boardId: widget.boardId);
                }

                // Build category list from full (unfiltered) templates.
                final categories = templates
                    .map((t) => t.category)
                    .whereType<String>()
                    .toSet()
                    .toList()
                  ..sort();

                final filtered = _filter(templates);

                return Column(
                  children: [
                    // Category filter chips
                    if (categories.isNotEmpty)
                      _CategoryBar(
                        categories: categories,
                        selected: _selectedCategory,
                        onSelect: (cat) => setState(() {
                          _selectedCategory =
                              _selectedCategory == cat ? null : cat;
                        }),
                      ),

                    // Results
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'No templates match "$_query".',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: kTextSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) =>
                                  _TemplateCard(template: filtered[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category filter bar ───────────────────────────────────────────────────────

class _CategoryBar extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: categories.map((cat) {
          final active = cat == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(cat),
              selected: active,
              onSelected: (_) => onSelect(cat),
              labelStyle: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : kTextPrimary,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
              backgroundColor: kBgPage,
              selectedColor: kBlueAccent,
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: active ? kBlueAccent : kBorderColor,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String boardId;
  const _EmptyState({required this.boardId});

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
              child: const Icon(Icons.description_outlined, color: kTextSecondary, size: 28),
            ),
            const SizedBox(height: 16),
            Text('No Templates Yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Upload a PDF form to get started.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => _UploadPdfSheet(boardId: boardId),
              ),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Template card ─────────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final FormTemplate template;
  const _TemplateCard({required this.template});

  @override
  Widget build(BuildContext context) {
    final totalFields = template.steps.fold<int>(
      0,
      (sum, step) => sum + step.fields.length,
    );

    return Card(
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
                Icons.picture_as_pdf_outlined,
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
                    template.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (template.category != null) ...[
                        _Chip(template.category!),
                        const SizedBox(width: 6),
                      ],
                      _Chip('$totalFields fields'),
                      const SizedBox(width: 6),
                      _Chip(
                        template.schemaReady ? 'Ready' : 'Processing',
                        color: template.schemaReady
                            ? kSuccessGreen
                            : kWarningAmber,
                      ),
                      if (template.schemaReady && template.fieldLabels.isEmpty) ...[
                        const SizedBox(width: 6),
                        const _Chip('Labels pending', color: kWarningAmber, icon: Icons.auto_awesome_outlined),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/templates/${template.id}/edit'),
              icon: const Icon(Icons.tune, size: 14),
              label: const Text('Edit Fields'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => context.push('/fill/new/${template.id}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(80, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Fill'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  const _Chip(this.label, {this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Upload PDF sheet ──────────────────────────────────────────────────────────

class _UploadPdfSheet extends ConsumerStatefulWidget {
  final String boardId;
  const _UploadPdfSheet({required this.boardId});

  @override
  ConsumerState<_UploadPdfSheet> createState() => _UploadPdfSheetState();
}

class _UploadPdfSheetState extends ConsumerState<_UploadPdfSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _fileName;
  Uint8List? _pdfBytes;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() {
      _pdfBytes = file.bytes;
      _fileName = file.name;
      // Pre-fill name from filename if empty.
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = file.name
            .replaceAll('.pdf', '')
            .replaceAll('_', ' ')
            .replaceAll('-', ' ');
      }
      _error = null;
    });
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pdfBytes == null) {
      setState(() => _error = 'Please select a PDF file.');
      return;
    }

    setState(() { _uploading = true; _error = null; });
    try {
      await TemplateService.uploadTemplate(
        pdfBytes: _pdfBytes!,
        name: _nameCtrl.text.trim(),
        boardId: widget.boardId,
        category: _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template uploaded successfully.')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Upload PDF Form', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // File picker
            GestureDetector(
              onTap: _uploading ? null : _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _pdfBytes != null ? kBlueAccent : kBorderColor,
                    width: _pdfBytes != null ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: _pdfBytes != null
                      ? kBlueAccent.withValues(alpha: 0.04)
                      : kBgPage,
                ),
                child: Column(
                  children: [
                    Icon(
                      _pdfBytes != null
                          ? Icons.picture_as_pdf
                          : Icons.upload_file_outlined,
                      size: 32,
                      color: _pdfBytes != null ? kBlueAccent : kTextSecondary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fileName ?? 'Tap to select a PDF',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _pdfBytes != null ? kTextPrimary : kTextSecondary,
                        fontWeight: _pdfBytes != null ? FontWeight.w500 : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_pdfBytes != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${(_pdfBytes!.length / 1024).toStringAsFixed(0)} KB — tap to change',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: kTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Form Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                hintText: 'e.g. Purchase, Disclosure, Lease',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_uploading ? 'Uploading…' : 'Upload Template'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Exported for use in other files that need to copy text to clipboard.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Link copied to clipboard.'),
      duration: Duration(seconds: 2),
    ),
  );
}
