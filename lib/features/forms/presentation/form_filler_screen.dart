import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/filled_form.dart';
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/models/transaction.dart' as tx_model;
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/services/pdf_stamper.dart';
import 'package:formtract/core/services/storage_service.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen wizard for filling a form template on behalf of a transaction.
///
/// Route params: txId (transaction id), templateId.
/// When txId == 'new', a placeholder transaction is used and the form is saved
/// as a standalone draft (useful for testing from the templates screen).
class FormFillerScreen extends ConsumerStatefulWidget {
  final String txId;
  final String templateId;

  const FormFillerScreen({
    required this.txId,
    required this.templateId,
    super.key,
  });

  @override
  ConsumerState<FormFillerScreen> createState() => _FormFillerScreenState();
}

class _FormFillerScreenState extends ConsumerState<FormFillerScreen> {
  // ── State ──────────────────────────────────────────────────────────────────

  FormTemplate? _template;
  FilledForm? _filledForm;

  int _step = 0;
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isGenerating = false;
  String? _error;
  String? _completedPdfUrl;

  Timer? _saveTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    try {
      final db = FirebaseFirestore.instance;

      // 1. Load template.
      final templateSnap = await db
          .collection('form_templates')
          .doc(widget.templateId)
          .get();
      if (!templateSnap.exists) throw Exception('Template not found.');
      final template = FormTemplate.fromFirestore(templateSnap);

      // 2. Load transaction if real.
      tx_model.Transaction? transaction;
      if (widget.txId != 'new') {
        final txSnap = await db
            .collection('transactions')
            .doc(widget.txId)
            .get();
        if (txSnap.exists) {
          transaction = tx_model.Transaction.fromFirestore(txSnap);
        }
      }

      // 3. Check for an existing draft.
      FilledForm? existing;
      if (widget.txId != 'new') {
        final q = await db
            .collection('transactions')
            .doc(widget.txId)
            .collection('filled_forms')
            .where('templateId', isEqualTo: widget.templateId)
            .where('status', isEqualTo: 'draft')
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          existing = FilledForm.fromFirestore(q.docs.first);
        }
      }

      // 4. Create new draft if needed.
      final filledForm =
          existing ?? await _createDraft(txId: widget.txId, template: template);

      // 5. Seed initial values from draft + autofill.
      final values = Map<String, dynamic>.from(filledForm.fieldValues);
      if (existing == null) {
        _autofill(values, template, transaction);
      }

      // 6. Build text controllers.
      final controllers = <String, TextEditingController>{};
      for (final step in template.steps) {
        for (final field in step.fields) {
          if (_isTextField(field.type)) {
            controllers[field.id] = TextEditingController(
              text: values[field.id]?.toString() ?? '',
            );
          }
        }
      }

      setState(() {
        _template = template;
        _filledForm = filledForm;
        _values.addAll(values);
        _controllers.addAll(controllers);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<FilledForm> _createDraft({
    required String txId,
    required FormTemplate template,
  }) async {
    final effectiveTxId = txId == 'new' ? 'standalone' : txId;
    final formId = await createFilledForm(
      txId: effectiveTxId,
      templateId: template.id,
      templateName: template.name,
    );
    return FilledForm(
      id: formId,
      transactionId: effectiveTxId,
      templateId: template.id,
      templateName: template.name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _autofill(
    Map<String, dynamic> values,
    FormTemplate template,
    tx_model.Transaction? transaction,
  ) {
    final agent = ref.read(authNotifierProvider);

    // Pre-fill agent info by matching common field name patterns.
    _fillMatching(values, template, [
      'broker name',
      'agent name',
    ], agent.userName);
    _fillMatching(values, template, [
      'broker email',
      'agent email',
    ], agent.userEmail);
  }

  void _fillMatching(
    Map<String, dynamic> values,
    FormTemplate template,
    List<String> keywords,
    String value,
  ) {
    if (value.isEmpty) return;
    for (final step in template.steps) {
      for (final field in step.fields) {
        final lower = field.id.toLowerCase();
        if (keywords.any(lower.contains) && !values.containsKey(field.id)) {
          values[field.id] = value;
        }
      }
    }
  }

  static bool _isTextField(FormFieldType type) => switch (type) {
    FormFieldType.text ||
    FormFieldType.email ||
    FormFieldType.phone ||
    FormFieldType.date ||
    FormFieldType.number ||
    FormFieldType.initials => true,
    _ => false,
  };

  // ── Auto-save ──────────────────────────────────────────────────────────────

  void _onFieldChanged(String fieldId, value) {
    setState(() => _values[fieldId] = value);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    final form = _filledForm;
    if (form == null) return;
    setState(() => _isSaving = true);
    try {
      // Uint8List (signature bytes) can't be stored in Firestore — skip them.
      final serializable = Map<String, dynamic>.from(_values)
        ..removeWhere((_, v) => v is List<int>);
      await saveFilledFormDraft(form.transactionId, form.id, serializable);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Step navigation ────────────────────────────────────────────────────────

  void _next() {
    final maxStep = (_template?.steps.length ?? 1) - 1;
    if (_step < maxStep) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  // ── PDF generation ─────────────────────────────────────────────────────────

  Future<void> _generatePdf() async {
    final template = _template;
    final form = _filledForm;
    final agent = ref.read(agentProfileProvider).value;
    if (template == null || form == null) return;

    setState(() => _isGenerating = true);
    try {
      // Download the original blank PDF.
      final pdfBytes = await StorageService.downloadTemplate(
        boardId: template.boardId,
        templateId: template.id,
      );
      if (pdfBytes == null) throw Exception('Could not download template PDF.');

      // Stamp field values.
      final stamped = PdfStamper.stamp(pdfBytes, _values);

      // Upload stamped PDF.
      final agentId =
          agent?.id ?? ref.read(authNotifierProvider).currentUser!.uid;
      final storagePath = await StorageService.uploadCompletedForm(
        pdfBytes: stamped,
        agentId: agentId,
        transactionId: form.transactionId,
        filledFormId: form.id,
      );

      // Mark FilledForm as complete.
      await completeFilledForm(form.transactionId, form.id, storagePath);

      // Get download URL for share/preview.
      final url = await StorageService.completedFormDownloadUrl(
        agentId: agentId,
        transactionId: form.transactionId,
        filledFormId: form.id,
      );

      setState(() => _completedPdfUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF generation failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(leading: const CloseButton()),
        body: Center(child: Text('Error: $_error')),
      );
    }
    if (_completedPdfUrl != null) {
      return _DoneScreen(
        templateName: _template?.name ?? '',
        pdfUrl: _completedPdfUrl!,
        onClose: () => context.pop(),
      );
    }

    final template = _template!;
    final steps = template.steps;
    final currentStep = steps[_step];
    final isLastStep = _step == steps.length - 1;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            _saveTimer?.cancel();
            await _save();
            if (context.mounted) context.pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${_step + 1} of ${steps.length} — ${currentStep.title}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Saved',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _StepProgressBar(current: _step, total: steps.length),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _FormStepView(
                step: currentStep,
                values: _values,
                controllers: _controllers,
                onChanged: _onFieldChanged,
              ),
            ),
          ),
          _BottomBar(
            isFirst: _step == 0,
            isLast: isLastStep,
            isGenerating: _isGenerating,
            onBack: _back,
            onNext: _next,
            onGenerate: _generatePdf,
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          for (int i = 0; i < total; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? kBlueAccent : kBorderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < total - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _FormStepView extends StatelessWidget {
  final FormStep step;
  final Map<String, dynamic> values;
  final Map<String, TextEditingController> controllers;
  // ignore: avoid_annotating_with_dynamic
  final void Function(String fieldId, dynamic value) onChanged;

  const _FormStepView({
    required this.step,
    required this.values,
    required this.controllers,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${step.fields.length} field${step.fields.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            ...step.fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _FieldWidget(
                  field: field,
                  value: values[field.id],
                  controller: controllers[field.id],
                  onChanged: (v) => onChanged(field.id, v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldWidget extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final TextEditingController? controller;
  final ValueChanged<dynamic> onChanged;

  const _FieldWidget({
    required this.field,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return switch (field.type) {
      FormFieldType.checkbox => _CheckboxField(
        label: field.label,
        value: value == true || value.toString() == 'true',
        onChanged: onChanged,
      ),
      FormFieldType.radio => _RadioField(
        label: field.label,
        options: field.options,
        value: value?.toString(),
        onChanged: onChanged,
      ),
      FormFieldType.signature => _SignaturePad(
        label: field.label,
        onChanged: onChanged,
      ),
      FormFieldType.dropdown => _DropdownField(
        label: field.label,
        options: field.options,
        value: value?.toString(),
        onChanged: onChanged,
      ),
      _ => _TextField(
        label: field.label,
        type: field.type,
        controller: controller!,
        onChanged: onChanged,
      ),
    };
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final FormFieldType type;
  final TextEditingController controller;
  final ValueChanged<dynamic> onChanged;

  const _TextField({
    required this.label,
    required this.type,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: switch (type) {
        FormFieldType.email => TextInputType.emailAddress,
        FormFieldType.phone => TextInputType.phone,
        FormFieldType.number => const TextInputType.numberWithOptions(
          decimal: true,
        ),
        _ => TextInputType.text,
      },
      textCapitalization: type == FormFieldType.initials
          ? TextCapitalization.characters
          : TextCapitalization.words,
      maxLength: type == FormFieldType.initials ? 4 : null,
      onChanged: onChanged,
    );
  }
}

class _CheckboxField extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<dynamic> onChanged;

  const _CheckboxField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<dynamic> onChanged;

  const _DropdownField({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return TextFormField(
        decoration: InputDecoration(labelText: label),
        initialValue: value ?? '',
        onChanged: onChanged,
      );
    }
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label),
      initialValue: options.contains(value) ? value : null,
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _RadioField extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<dynamic> onChanged;

  const _RadioField({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return TextFormField(
        decoration: InputDecoration(labelText: label),
        initialValue: value ?? '',
        onChanged: onChanged,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        RadioGroup<String>(
          groupValue: value,
          onChanged: (v) => onChanged(v),
          child: Column(
            children: options
                .map(
                  (opt) => RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      opt,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    value: opt,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SignaturePad extends StatefulWidget {
  final String label;
  final ValueChanged<dynamic> onChanged;

  const _SignaturePad({required this.label, required this.onChanged});

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;
  final _padKey = GlobalKey();

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _current = [d.localPosition];
      _strokes.add(_current!);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _current?.add(d.localPosition));
  }

  Future<void> _onPanEnd(DragEndDetails _) async {
    _current = null;
    final bytes = await _export();
    widget.onChanged(bytes);
  }

  Future<List<int>?> _export() async {
    if (_strokes.isEmpty) return null;
    final box = _padKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(400, 120);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke[0], 1.5, paint);
        continue;
      }
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _clear() {
    setState(() => _strokes.clear());
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _strokes.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label, style: Theme.of(context).textTheme.labelSmall),
            if (!isEmpty) ...[
              const Spacer(),
              GestureDetector(
                onTap: _clear,
                child: Text(
                  'Clear',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: kBlueAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Container(
          key: _padKey,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(
              color: isEmpty ? kBorderColor : kBlueAccent,
              width: isEmpty ? 1 : 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          clipBehavior: Clip.hardEdge,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _StrokePainter(_strokes),
              child: isEmpty
                  ? Center(
                      child: Text(
                        'Sign here',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: kTextSecondary),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke[0], 1.5, paint);
        continue;
      }
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

class _BottomBar extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final bool isGenerating;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onGenerate;

  const _BottomBar({
    required this.isFirst,
    required this.isLast,
    required this.isGenerating,
    required this.onBack,
    required this.onNext,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          if (!isFirst)
            OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(minimumSize: const Size(100, 44)),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (isLast)
            FilledButton.icon(
              onPressed: isGenerating ? null : onGenerate,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Generate PDF'),
              style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
            )
          else
            FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }
}

class _DoneScreen extends StatelessWidget {
  final String templateName;
  final String pdfUrl;
  final VoidCallback onClose;

  const _DoneScreen({
    required this.templateName,
    required this.pdfUrl,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Form Complete'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kSuccessGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: kSuccessGreen,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'PDF Generated!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                templateName,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(pdfUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open PDF'),
                style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onClose, child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
