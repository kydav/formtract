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
      List<FormFieldDef> acroFields = [];
      if (bytes != null) {
        final doc = sf_pdf.PdfDocument(inputBytes: bytes);
        pageSizes = List.generate(
          doc.pages.count,
          (i) => Size(doc.pages[i].size.width, doc.pages[i].size.height),
        );
        // Extract exact AcroForm field positions — much more accurate than AI estimates.
        acroFields = _extractAcroFields(doc, pageSizes);
        doc.dispose();
      }

      // Merge: if Firestore fields lack positions but AcroForm fields exist,
      // match by name and apply exact PDF bounds. If no Firestore fields yet,
      // use AcroForm fields directly.
      List<FormFieldDef> mergedFields;
      if (fields.isEmpty && acroFields.isNotEmpty) {
        mergedFields = acroFields;
      } else if (fields.isNotEmpty && acroFields.isNotEmpty) {
        mergedFields = _applyAcroPositions(fields, acroFields);
      } else {
        mergedFields = List.from(fields);
      }

      if (!mounted) return;
      setState(() {
        _template = snap;
        _fields = mergedFields;
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

  // ── AcroForm extraction ───────────────────────────────────────────────────

  /// Extracts field positions directly from PDF AcroForm data.
  /// Syncfusion returns bounds in PDF native coordinates: y=0 at page BOTTOM,
  /// increasing upward. Convert to screen coords with (ph - b.top) / ph.
  List<FormFieldDef> _extractAcroFields(
    sf_pdf.PdfDocument doc,
    List<Size> pageSizes,
  ) {
    final result = <FormFieldDef>[];
    try {
      final form = doc.form;
      for (int i = 0; i < form.fields.count; i++) {
        final field = form.fields[i];
        final page = field.page;
        if (page == null) continue;
        final pageIndex = doc.pages.indexOf(page);
        if (pageIndex < 0 || pageIndex >= pageSizes.length) continue;
        final pw = pageSizes[pageIndex].width;
        final ph = pageSizes[pageIndex].height;
        final b = field.bounds;
        result.add(
          FormFieldDef(
            id:
                (field.name?.isNotEmpty == true ? field.name : 'field$i') ??
                'field$i',
            label:
                (field.name?.isNotEmpty == true
                    ? field.name
                    : 'Field ${i + 1}') ??
                'Field ${i + 1}',
            type: _pdfFieldType(field),
            page: pageIndex + 1,
            x: (b.left / pw * 100).clamp(0, 100),
            // PDF native: y=0 at bottom. Convert to screen y (0=top).
            y: ((ph - b.top) / ph * 100).clamp(0, 100),
            width: (b.width / pw * 100).clamp(1, 100),
            height: (b.height / ph * 100).clamp(1, 100),
          ),
        );
      }
    } catch (_) {}
    return result;
  }

  FormFieldType _pdfFieldType(sf_pdf.PdfField field) {
    if (field is sf_pdf.PdfCheckBoxField) return FormFieldType.checkbox;
    if (field is sf_pdf.PdfRadioButtonListField) return FormFieldType.radio;
    if (field is sf_pdf.PdfComboBoxField) return FormFieldType.dropdown;
    if (field is sf_pdf.PdfSignatureField) return FormFieldType.signature;
    return FormFieldType.text;
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
      var fields = rawFields
          .map((m) => FormFieldDef.fromMap(m.cast<String, dynamic>()))
          .toList();

      // Override AI positions with exact AcroForm positions where available.
      List<FormFieldDef> acroFields = [];
      if (_pdfBytes != null) {
        try {
          final doc = sf_pdf.PdfDocument(inputBytes: _pdfBytes!);
          acroFields = _extractAcroFields(doc, _pageSizes);
          doc.dispose();
          if (acroFields.isNotEmpty) {
            fields = _applyAcroPositions(fields, acroFields);
          }
        } catch (_) {}
      }

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
    // Generate a unique ID that won't collide with existing fields.
    final existing = _fields.map((f) => f.id).toSet();
    var n = _fields.length + 1;
    var id = 'field$n';
    while (existing.contains(id)) {
      n++;
      id = 'field$n';
    }
    final newField = FormFieldDef(
      id: id,
      label: 'New Field',
      type: FormFieldType.text,
      page: _viewingPage,
      x: 32,   // center-ish horizontally
      y: 45,   // center of page
      width: 35,
      height: 4,
    );
    setState(() {
      _fields.add(newField);
      _selectedIndex = _fields.length - 1;
    });
  }

  void _deleteField(int index) {
    setState(() {
      _fields.removeAt(index);
      if (_fields.isEmpty) {
        _selectedIndex = 0;
      } else {
        _selectedIndex = _selectedIndex
            .clamp(0, _fields.length - 1);
      }
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
        // AI detect — secondary, icon-only to save space.
        IconButton(
          onPressed: _detecting ? null : _detectFields,
          tooltip: _fields.isEmpty ? 'Detect fields with AI' : 'Re-detect fields with AI',
          icon: _detecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                )
              : const Icon(Icons.auto_awesome, size: 18, color: Colors.white70),
        ),
        // Add Field — primary manual action.
        TextButton.icon(
          onPressed: _addField,
          icon: const Icon(Icons.add, size: 16, color: Colors.white),
          label: const Text(
            'Add Field',
            style: TextStyle(color: Colors.white, fontSize: 13),
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
        SizedBox(
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

  // ── AcroForm position merge ───────────────────────────────────────────────
  //
  // Normalizes names by stripping all non-alphanumeric characters so that
  // AcroForm "Other Compensation" matches AI id "otherCompensation".
  // Falls back to reading-order sort match when page field counts agree.
  static String _normName(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  List<FormFieldDef> _applyAcroPositions(
    List<FormFieldDef> aiFields,
    List<FormFieldDef> acroFields,
  ) {
    List<FormFieldDef> sortByYX(List<FormFieldDef> list) =>
        [...list]..sort((a, b) {
          final yComp = (a.y ?? 0.0).compareTo(b.y ?? 0.0);
          return yComp != 0 ? yComp : (a.x ?? 0.0).compareTo(b.x ?? 0.0);
        });

    // Build a normalized-name lookup across ALL AcroForm fields (not per-page),
    // because AI page numbers may differ from AcroForm page numbers.
    final acroByNorm = <String, FormFieldDef>{};
    for (final f in acroFields) {
      acroByNorm[_normName(f.id)] = f;
    }

    final aiByPage = <int, List<FormFieldDef>>{};
    final acroByPage = <int, List<FormFieldDef>>{};
    for (final f in aiFields) {
      aiByPage.putIfAbsent(f.page ?? 1, () => []).add(f);
    }
    for (final f in acroFields) {
      acroByPage.putIfAbsent(f.page ?? 1, () => []).add(f);
    }

    final replacements = <String, FormFieldDef>{};

    // First pass: normalized name match across entire AcroForm (handles
    // mismatched page counts and descriptive AcroForm field names).
    for (final f in aiFields) {
      final match = acroByNorm[_normName(f.id)] ?? acroByNorm[_normName(f.label)];
      if (match != null) replacements[f.id] = match;
    }

    // Second pass: per-page reading-order sort for any remaining unmatched fields
    // (handles forms where per-page counts agree but names are generic).
    for (final page in aiByPage.keys) {
      final ai = sortByYX(aiByPage[page]!).where((f) => !replacements.containsKey(f.id)).toList();
      final acro = acroByPage[page];
      if (acro == null || ai.isEmpty) continue;
      final sortedAcro = sortByYX(acro);
      if (ai.length == sortedAcro.length) {
        for (int i = 0; i < ai.length; i++) {
          replacements[ai[i].id] = sortedAcro[i];
        }
      }
    }

    return aiFields.map((f) {
      final match = replacements[f.id];
      if (match == null) return f;
      return f.copyWith(x: match.x, y: match.y, width: match.width, height: match.height);
    }).toList();
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
        final viewerHeight = constraints.maxHeight;

        // Page aspect ratio drives overlay coordinate scaling.
        Size pageSize = const Size(612, 792);
        if (_pageSizes.isNotEmpty && _viewingPage <= _pageSizes.length) {
          pageSize = _pageSizes[_viewingPage - 1];
        }

        // SfPdfViewer fits the page inside the available viewport (both axes),
        // keeping aspect ratio and centering. Calculate the actual rendered page
        // bounds so overlays align precisely.
        final scaleX = viewerWidth / pageSize.width;
        final scaleY = viewerHeight > 0
            ? viewerHeight / pageSize.height
            : scaleX;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final renderedPageWidth = pageSize.width * scale;
        final renderedPageHeight = pageSize.height * scale;
        final pageLeft = (viewerWidth - renderedPageWidth) / 2;
        final pageTop = (viewerHeight - renderedPageHeight) / 2;

        // Only overlay fields that have AI-detected positions.
        // AcroForm-only fields have null x/y and must be navigated via the panel.
        final currentPageFields = _fields
            .where((f) => (f.page ?? 1) == _viewingPage && f.hasPosition)
            .toList();

        final hasAnyPositions = _fields.any((f) => f.hasPosition);

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

            // Field overlays — draggable + resizable percentage-coord boxes.
            ...currentPageFields.map((field) {
              final fieldIndex = _fields.indexOf(field);
              final isSelected = fieldIndex == _selectedIndex;
              final color = isSelected ? kBlueAccent : Colors.orange;

              final left = pageLeft + (field.x ?? 0) / 100 * renderedPageWidth;
              final top = pageTop + (field.y ?? 0) / 100 * renderedPageHeight;
              final width =
                  ((field.width ?? 10) / 100 * renderedPageWidth).clamp(
                    10.0,
                    renderedPageWidth,
                  );
              final height = ((field.height ?? 4) / 100 * renderedPageHeight)
                  .clamp(8.0, renderedPageHeight);

              return Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectField(fieldIndex),
                  onPanUpdate: (d) {
                    // Drag moves the field
                    final f = _fields[fieldIndex];
                    final newX =
                        ((f.x ?? 0) + d.delta.dx / renderedPageWidth * 100)
                            .clamp(0.0, 100.0);
                    final newY =
                        ((f.y ?? 0) + d.delta.dy / renderedPageHeight * 100)
                            .clamp(0.0, 100.0);
                    setState(
                      () => _fields[fieldIndex] = f.copyWith(x: newX, y: newY),
                    );
                    if (fieldIndex != _selectedIndex) {
                      setState(() => _selectedIndex = fieldIndex);
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Field box
                      Container(
                        width: double.infinity,
                        height: double.infinity,
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
                      // SE resize handle (only when selected)
                      if (isSelected)
                        Positioned(
                          right: -6,
                          bottom: -6,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) {
                              final f = _fields[fieldIndex];
                              final newW =
                                  ((f.width ?? 10) +
                                          d.delta.dx / renderedPageWidth * 100)
                                      .clamp(2.0, 100.0);
                              final newH =
                                  ((f.height ?? 4) +
                                          d.delta.dy / renderedPageHeight * 100)
                                      .clamp(1.0, 50.0);
                              setState(
                                () => _fields[fieldIndex] = f.copyWith(
                                  width: newW,
                                  height: newH,
                                ),
                              );
                            },
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: kBlueAccent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Icon(
                                Icons.open_in_full,
                                size: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),

            // Page indicator
            if (_pageSizes.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Page $_viewingPage of ${_pageSizes.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),

            // Banner when no fields have positions yet.
            if (!hasAnyPositions && _fields.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: kWarningAmber.withValues(alpha: 0.92),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Fields have no positions — use "Add Field" to place them on the PDF.',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _addField,
                        child: const Text(
                          'Add Field',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
              const Icon(Icons.add_box_outlined, size: 40, color: kTextSecondary),
              const SizedBox(height: 12),
              const Text(
                'No fields yet',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add fields manually and drag them into position on the PDF.',
                style: TextStyle(color: kTextSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _addField,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Field'),
                style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _detecting ? null : _detectFields,
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('Auto-detect with AI', style: TextStyle(fontSize: 12)),
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
        SizedBox(
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
