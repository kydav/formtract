import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/services/storage_service.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

// ── Contact mapping options ───────────────────────────────────────────────────

const _kMappingOptions = [
  (null, 'None'),
  ('agent.name', 'Agent Name'),
  ('agent.email', 'Agent Email'),
  ('buyer.fullName', 'Buyer Full Name'),
  ('buyer.firstName', 'Buyer First Name'),
  ('buyer.lastName', 'Buyer Last Name'),
  ('buyer.email', 'Buyer Email'),
  ('buyer.phone', 'Buyer Phone'),
  ('buyer.address', 'Buyer Address'),
  ('property.address', 'Property Address'),
  ('property.city', 'Property City'),
  ('property.state', 'Property State'),
  ('property.zipCode', 'Property Zip Code'),
  ('property.price', 'Purchase Price'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class TemplateEditorScreen extends ConsumerStatefulWidget {
  final String templateId;
  const TemplateEditorScreen({required this.templateId, super.key});

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  FormTemplate? _template;
  List<FormFieldDef> _fields = [];
  int _selectedIndex = 0;
  bool _loading = true;
  bool _saving = false;
  bool _detecting = false;
  String? _error;

  Uint8List? _pdfBytes;
  List<Size> _pageSizes = []; // PDF page dimensions in points
  int _viewingPage = 1;
  final _viewerController = PdfViewerController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _viewerController.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      // Wait for Firestore template via provider.
      final snap = await ref.read(
        formTemplateByIdProvider(widget.templateId).future,
      );
      if (snap == null) throw Exception('Template not found.');

      // Flatten steps → field list.
      final fields = snap.steps.expand((s) => s.fields).toList();

      // Download PDF to get page dimensions and for viewer.
      final bytes = await StorageService.downloadTemplate(
        boardId: snap.boardId,
        templateId: snap.id,
      );

      List<Size> pageSizes = [];
      if (bytes != null) {
        final doc = sf_pdf.PdfDocument(inputBytes: bytes);
        pageSizes = List.generate(
          doc.pages.count,
          (i) => Size(doc.pages[i].size.width, doc.pages[i].size.height),
        );
        doc.dispose();
      }

      if (!mounted) return;
      setState(() {
        _template = snap;
        _fields = List.from(fields);
        _pdfBytes = bytes;
        _pageSizes = pageSizes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── AI detection ──────────────────────────────────────────────────────────

  Future<void> _detectFields() async {
    final template = _template;
    if (template == null) return;
    setState(() => _detecting = true);
    try {
      final rawFields = await detectFormFieldsViaAI(
        templateId: template.id,
        boardId: template.boardId,
      );
      final fields = rawFields
          .map((m) => FormFieldDef.fromMap(m.cast<String, dynamic>()))
          .toList();
      setState(() {
        _fields = fields;
        _selectedIndex = 0;
        _viewingPage = fields.isNotEmpty ? (fields.first.page ?? 1) : 1;
      });
      _jumpToPage(_viewingPage);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Detection failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final template = _template;
    if (template == null) return;
    setState(() => _saving = true);
    try {
      // Group fields by page into FormSteps.
      final byPage = <int, List<FormFieldDef>>{};
      for (final f in _fields) {
        final page = f.page ?? 1;
        byPage.putIfAbsent(page, () => []).add(f);
      }
      final steps = byPage.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final formSteps = steps
          .map((e) => FormStep(title: 'Page ${e.key}', fields: e.value))
          .toList();

      await saveTemplateSteps(template.id, formSteps);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Template saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _selectField(int index) {
    if (index < 0 || index >= _fields.length) return;
    final field = _fields[index];
    final page = field.page ?? 1;
    setState(() {
      _selectedIndex = index;
      _viewingPage = page;
    });
    _jumpToPage(page);
  }

  void _jumpToPage(int page) {
    try {
      _viewerController.jumpToPage(page);
    } catch (_) {}
  }

  void _addField() {
    final page = _viewingPage;
    final newField = FormFieldDef(
      id: 'field${_fields.length + 1}',
      label: 'New Field',
      type: FormFieldType.text,
      page: page,
      x: 10,
      y: 10,
      width: 30,
      height: 5,
    );
    setState(() {
      _fields.add(newField);
      _selectedIndex = _fields.length - 1;
    });
  }

  void _deleteField(int index) {
    if (_fields.length <= 1) return;
    setState(() {
      _fields.removeAt(index);
      _selectedIndex =
          (_selectedIndex >= _fields.length
                  ? _fields.length - 1
                  : _selectedIndex)
              .clamp(0, _fields.length - 1);
    });
  }

  void _updateField(FormFieldDef updated) {
    setState(() => _fields[_selectedIndex] = updated);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: _buildAppBar(),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: kNavyDark,
      foregroundColor: Colors.white,
      title: Text(
        _template != null ? 'Edit: ${_template!.name}' : 'Template Editor',
        style: const TextStyle(fontSize: 15),
      ),
      actions: [
        if (_fields.isNotEmpty)
          TextButton.icon(
            onPressed: _detecting ? null : _detectFields,
            icon: _detecting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white70,
                  ),
            label: Text(
              'Re-detect',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ),
        if (_fields.isEmpty)
          TextButton.icon(
            onPressed: _detecting ? null : _detectFields,
            icon: _detecting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white70,
                  ),
            label: Text(
              'Detect Fields',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: (_saving || _fields.isEmpty) ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: kBlueAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(80, 36),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(child: _buildPdfPane()),
        Container(
          width: 360,
          // decoration: const BoxDecoration(
          //   color: Colors.white,
          //   border: Border(left: BorderSide(color: kBorderColor)),
          // ),
          child: _buildFieldPanel(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.52,
          child: _buildPdfPane(),
        ),
        const Divider(height: 1),
        Expanded(child: _buildFieldPanel()),
      ],
    );
  }

  // ── PDF pane ──────────────────────────────────────────────────────────────

  Widget _buildPdfPane() {
    if (_pdfBytes == null) {
      return const Center(child: Text('PDF not available'));
    }
    if (_detecting) {
      return Container(
        color: Colors.black.withValues(alpha: 0.03),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Detecting fields with AI…'),
            ],
          ),
        ),
      );
    }

    // SfPdfViewer requires bounded parent constraints — do NOT wrap in
    // SingleChildScrollView. Let it fill the available pane and handle
    // scrolling internally (single-page mode navigates via controller).
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewerWidth = constraints.maxWidth;

        // Page aspect ratio drives overlay coordinate scaling.
        Size pageSize = const Size(612, 792);
        if (_pageSizes.isNotEmpty && _viewingPage <= _pageSizes.length) {
          pageSize = _pageSizes[_viewingPage - 1];
        }
        // Height the PDF page occupies when scaled to fill viewerWidth.
        final renderedPageHeight = viewerWidth / pageSize.width * pageSize.height;

        final currentPageFields = _fields
            .where((f) => (f.page ?? 1) == _viewingPage)
            .toList();

        return Stack(
          children: [
            // PDF fills the entire pane; SfPdfViewer handles its own scrolling.
            SfPdfViewer.memory(
              _pdfBytes!,
              controller: _viewerController,
              pageLayoutMode: PdfPageLayoutMode.single,
              enableDoubleTapZooming: false,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              canShowPageLoadingIndicator: false,
              pageSpacing: 0,
              onPageChanged: (details) {
                if (details.newPageNumber != _viewingPage) {
                  setState(() => _viewingPage = details.newPageNumber);
                }
              },
            ),

            // Field overlays — percentage coords scaled to rendered page size.
            ...currentPageFields.map((field) {
              final fieldIndex = _fields.indexOf(field);
              final isSelected = fieldIndex == _selectedIndex;
              final color = isSelected ? kBlueAccent : Colors.orange;
              return Positioned(
                left: (field.x ?? 0) / 100 * viewerWidth,
                top: (field.y ?? 0) / 100 * renderedPageHeight,
                width: ((field.width ?? 10) / 100 * viewerWidth)
                    .clamp(20.0, viewerWidth),
                height: ((field.height ?? 4) / 100 * renderedPageHeight)
                    .clamp(14.0, renderedPageHeight),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectField(fieldIndex),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: color,
                        width: isSelected ? 2 : 1,
                      ),
                      color: color.withValues(
                        alpha: isSelected ? 0.18 : 0.08,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        color: color,
                        child: Text(
                          '${fieldIndex + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ── Field panel ───────────────────────────────────────────────────────────

  Widget _buildFieldPanel() {
    if (_fields.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 40, color: kTextSecondary),
              const SizedBox(height: 12),
              const Text(
                'No fields yet',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap "Detect Fields" to extract fields from the PDF automatically.',
                style: TextStyle(color: kTextSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _addField,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Field Manually'),
              ),
            ],
          ),
        ),
      );
    }

    final selected = _fields[_selectedIndex];

    return Column(
      children: [
        // Navigation header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          // decoration: const BoxDecoration(
          //   border: Border(bottom: BorderSide(color: kBorderColor)),
          // ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _selectedIndex > 0
                    ? () => _selectField(_selectedIndex - 1)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Expanded(
                child: Text(
                  'Field ${_selectedIndex + 1} of ${_fields.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _selectedIndex < _fields.length - 1
                    ? () => _selectField(_selectedIndex + 1)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Add field',
                onPressed: _addField,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // Field editor
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _FieldEditor(
              key: ValueKey(_selectedIndex),
              field: selected,
              fieldNumber: _selectedIndex + 1,
              pageCount: _pageSizes.length,
              onChanged: _updateField,
              onDelete: _fields.length > 1
                  ? () => _deleteField(_selectedIndex)
                  : null,
            ),
          ),
        ),

        // Field list mini-nav
        Container(
          height: 160,
          // decoration: const BoxDecoration(
          //   border: Border(top: BorderSide(color: kBorderColor)),
          // ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _fields.length,
            itemBuilder: (context, i) {
              final f = _fields[i];
              final isSelected = i == _selectedIndex;
              return ListTile(
                dense: true,
                selected: isSelected,
                selectedTileColor: kBlueAccent.withValues(alpha: 0.06),
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isSelected ? kBlueAccent : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${f.type.name}${f.page != null ? ' · p${f.page}' : ''}${f.contactMapping != null ? ' · ${f.contactMapping}' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => _selectField(i),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Field editor widget ───────────────────────────────────────────────────────

class _FieldEditor extends StatefulWidget {
  final FormFieldDef field;
  final int fieldNumber;
  final int pageCount;
  final ValueChanged<FormFieldDef> onChanged;
  final VoidCallback? onDelete;

  const _FieldEditor({
    required this.field,
    required this.fieldNumber,
    required this.pageCount,
    required this.onChanged,
    this.onDelete,
    super.key,
  });

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late TextEditingController _labelCtrl;
  late TextEditingController _idCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.field.label);
    _idCtrl = TextEditingController(text: widget.field.id);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  void _emit(FormFieldDef updated) => widget.onChanged(updated);

  @override
  Widget build(BuildContext context) {
    final f = widget.field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page badge
        if (f.page != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kBlueAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Page ${f.page}',
              style: const TextStyle(
                fontSize: 11,
                color: kBlueAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        const SizedBox(height: 14),

        // Label
        TextFormField(
          controller: _labelCtrl,
          decoration: const InputDecoration(labelText: 'Label', isDense: true),
          onChanged: (v) => _emit(f.copyWith(label: v)),
        ),
        const SizedBox(height: 12),

        // ID
        TextFormField(
          controller: _idCtrl,
          decoration: const InputDecoration(
            labelText: 'Field ID',
            isDense: true,
            helperText: 'camelCase, used in PDF stamping',
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          onChanged: (v) => _emit(f.copyWith(id: v)),
        ),
        const SizedBox(height: 12),

        // Type
        DropdownButtonFormField<FormFieldType>(
          initialValue: f.type,
          decoration: const InputDecoration(labelText: 'Type', isDense: true),
          items: FormFieldType.values
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t.name, style: const TextStyle(fontSize: 14)),
                ),
              )
              .toList(),
          onChanged: (v) => _emit(f.copyWith(type: v)),
        ),
        const SizedBox(height: 12),

        // Contact mapping
        DropdownButtonFormField<String?>(
          initialValue: f.contactMapping,
          decoration: const InputDecoration(
            labelText: 'Auto-fill from',
            isDense: true,
            helperText: 'Automatically fills this field from contact data',
          ),
          items: _kMappingOptions
              .map(
                (opt) => DropdownMenuItem<String?>(
                  value: opt.$1,
                  child: Text(
                    opt.$2,
                    style: TextStyle(
                      fontSize: 14,
                      color: opt.$1 == null ? kTextSecondary : kTextPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => v == null
              ? _emit(f.copyWith(clearContactMapping: true))
              : _emit(f.copyWith(contactMapping: v)),
        ),
        const SizedBox(height: 12),

        // Required toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Required', style: TextStyle(fontSize: 14)),
          value: f.required,
          onChanged: (v) => _emit(f.copyWith(required: v)),
          dense: true,
        ),

        // Page number (if has position)
        if (f.page != null && widget.pageCount > 1) ...[
          const Divider(height: 24),
          const Text(
            'Position',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: f.page,
            decoration: const InputDecoration(labelText: 'Page', isDense: true),
            items: List.generate(
              widget.pageCount,
              (i) =>
                  DropdownMenuItem(value: i + 1, child: Text('Page ${i + 1}')),
            ),
            onChanged: (v) => _emit(f.copyWith(page: v)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PosField(
                  label: 'X %',
                  value: f.x ?? 0,
                  onChanged: (v) => _emit(f.copyWith(x: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PosField(
                  label: 'Y %',
                  value: f.y ?? 0,
                  onChanged: (v) => _emit(f.copyWith(y: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PosField(
                  label: 'W %',
                  value: f.width ?? 10,
                  onChanged: (v) => _emit(f.copyWith(width: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PosField(
                  label: 'H %',
                  value: f.height ?? 4,
                  onChanged: (v) => _emit(f.copyWith(height: v)),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 20),

        if (widget.onDelete != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onDelete,
              icon: const Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.red,
              ),
              label: const Text(
                'Delete Field',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(0, 40),
              ),
            ),
          ),
      ],
    );
  }
}

class _PosField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _PosField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_PosField> createState() => _PosFieldState();
}

class _PosFieldState extends State<_PosField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(_PosField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      decoration: InputDecoration(labelText: widget.label, isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) {
        final d = double.tryParse(v);
        if (d != null) widget.onChanged(d.clamp(0, 100));
      },
    );
  }
}
