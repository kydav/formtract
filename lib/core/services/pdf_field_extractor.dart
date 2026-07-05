import 'dart:typed_data';

import 'package:formtract/core/models/form_template.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts AcroForm fields from a PDF and organises them into [FormStep]s.
class PdfFieldExtractor {
  static List<FormStep> extractSteps(Uint8List pdfBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    final fields = _extractFields(document);
    document.dispose();
    return _groupIntoSteps(fields);
  }

  // ── Field extraction ──────────────────────────────────────────────────────

  static List<FormFieldDef> _extractFields(PdfDocument document) {
    final result = <FormFieldDef>[];
    final form = document.form;
    for (int i = 0; i < form.fields.count; i++) {
      final field = form.fields[i];
      final name = field.name ?? '';
      if (name.isEmpty) continue;
      if (_isSectionHeader(name)) continue;
      result.add(_toFieldDef(field, name));
    }
    return result;
  }

  // Section header nodes (e.g. "Section 3", "Section 7.2") are non-interactive
  // parent nodes in the AcroForm tree — skip them.
  static bool _isSectionHeader(String name) =>
      RegExp(r'^Section\s+[\d.]+$').hasMatch(name);

  static FormFieldDef _toFieldDef(PdfField field, String name) {
    return FormFieldDef(
      id: name,
      label: _toLabel(name),
      type: _classifyType(field, name),
    );
  }

  // ── Field type classification ──────────────────────────────────────────────

  static FormFieldType _classifyType(PdfField field, String name) {
    if (field is PdfSignatureField) return FormFieldType.signature;
    if (field is PdfCheckBoxField) return FormFieldType.checkbox;
    if (field is PdfRadioButtonListField) return FormFieldType.radio;
    if (field is PdfComboBoxField || field is PdfListBoxField) {
      return FormFieldType.dropdown;
    }
    // PdfTextBoxField — classify by name keywords
    final l = name.toLowerCase();
    if (_has(l, ['email'])) return FormFieldType.email;
    if (_has(l, ['phone', 'cell', 'fax', 'telephone'])) return FormFieldType.phone;
    if (_has(l, ['date', 'day', 'month', 'year'])) return FormFieldType.date;
    if (_has(l, ['initial'])) return FormFieldType.initials;
    if (_has(l, [
      'amount', 'fee', 'price', 'percentage', 'commission',
      'retainer', 'dollars', 'hourly', 'flat fee',
    ])) return FormFieldType.number;
    return FormFieldType.text;
  }

  static bool _has(String lower, List<String> keywords) =>
      keywords.any(lower.contains);

  // ── Label generation ───────────────────────────────────────────────────────

  static String _toLabel(String name) {
    var label = name
        .replaceAll(RegExp(r'^Section\s+[\d.]+\s+'), '')
        .replaceAll('_', ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ')
        .replaceAll('/', ' / ')
        .trim();
    if (label.isEmpty) label = name;
    return label
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.length == 1 ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ── Step grouping ──────────────────────────────────────────────────────────

  static const _stepOrder = [
    'Agreement Terms',
    'Buyer Information',
    'Brokerage',
    'Compensation',
    'Options & Elections',
    'Additional Provisions',
    'Signatures',
  ];

  static List<FormStep> _groupIntoSteps(List<FormFieldDef> fields) {
    final Map<String, List<FormFieldDef>> buckets = {
      for (final s in _stepOrder) s: [],
    };
    for (final field in fields) {
      buckets[_bucketFor(field)]!.add(field);
    }
    return [
      for (final step in _stepOrder)
        if (buckets[step]!.isNotEmpty)
          FormStep(title: step, fields: buckets[step]!),
    ];
  }

  static String _bucketFor(FormFieldDef f) {
    if (f.type == FormFieldType.signature) return 'Signatures';
    final l = f.id.toLowerCase();

    if (_has(l, ['buyer', 'buyers', 'client'])) return 'Buyer Information';
    if (_has(l, [
      'broker', 'brokerage', 'agent', 'firm', 'designated', 'managing', 'license',
    ])) return 'Brokerage';
    if (_has(l, [
      'fee', 'commission', 'retainer', 'compensation', 'percentage',
      'amount', 'dollars', 'hourly', 'flat fee', 'lease', 'success fee',
      'purchase price', 'price range',
    ])) return 'Compensation';
    if (_has(l, ['date', 'period', 'term', 'expir', 'holdover', 'begin', 'start', 'end'])) {
      return 'Agreement Terms';
    }
    if (_has(l, ['provision', 'attachment', 'additional', 'confidential', 'showing'])) {
      return 'Additional Provisions';
    }
    if (f.type == FormFieldType.checkbox || f.type == FormFieldType.radio) {
      return 'Options & Elections';
    }
    return 'Agreement Terms';
  }
}
