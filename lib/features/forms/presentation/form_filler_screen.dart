import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/filled_form.dart';
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/models/signing_request.dart';
import 'package:formtract/core/models/transaction.dart' as tx_model;
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/services/pdf_stamper.dart';
import 'package:formtract/core/services/storage_service.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Represents one AcroForm field extracted from the PDF.
class _AcroField {
  final String name; // raw AcroForm name — key for stamping
  final String label; // display label (prettified or from template)
  final FormFieldType type;
  final int page;
  final List<String> options;
  // Bounds in Syncfusion device coords (points, y from top of page).
  final double rawLeft;
  final double rawTop;
  final double rawWidth;
  final double rawHeight;
  final double pageWidth;
  final double pageHeight;

  const _AcroField({
    required this.name,
    required this.label,
    required this.type,
    required this.page,
    this.options = const [],
    this.rawLeft = 0,
    this.rawTop = 0,
    this.rawWidth = 0,
    this.rawHeight = 0,
    this.pageWidth = 612,
    this.pageHeight = 792,
  });

  bool get hasBounds => rawWidth > 0 && rawHeight > 0;

  double get xFrac => pageWidth > 0 ? rawLeft / pageWidth : 0;
  double get yFrac => pageHeight > 0 ? rawTop / pageHeight : 0;
  double get wFrac => pageWidth > 0 ? rawWidth / pageWidth : 0;
  double get hFrac => pageHeight > 0 ? rawHeight / pageHeight : 0;
}

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

  // AcroForm-driven fields (source of truth when PDF is available).
  List<_AcroField> _acroFields = [];
  List<int> _acroPages = []; // sorted unique page numbers with fields

  // _step indexes into _acroPages.
  int _step = 0;

  // Values keyed by AcroForm field NAME (not template field ID).
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isGenerating = false;
  bool _isRequestingSigning = false;
  String? _error;
  String? _completedPdfUrl;

  Uint8List? _blankPdfBytes;
  Uint8List? _previewPdfBytes;
  int _previewVersion = 0;
  final _pdfController = PdfViewerController();

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
    _pdfController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    try {
      final db = FirebaseFirestore.instance;

      // 1. Load template (for autofill hints and contact mapping).
      final templateSnap = await db
          .collection('form_templates')
          .doc(widget.templateId)
          .get();
      if (!templateSnap.exists) throw Exception('Template not found.');
      final template = FormTemplate.fromFirestore(templateSnap);

      // 2. Load transaction.
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

      // 3. Check for existing draft.
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
      final filledForm =
          existing ?? await _createDraft(txId: widget.txId, template: template);

      // 4. Download PDF and extract AcroForm fields.
      final pdfBytes = await StorageService.downloadTemplate(
        boardId: template.boardId,
        templateId: template.id,
      );

      List<_AcroField> acroFields = [];
      if (pdfBytes != null) {
        acroFields = _extractAcroFields(pdfBytes, template);
      }

      // Fall back to template fields if AcroForm extraction found nothing.
      if (acroFields.isEmpty) {
        acroFields = template.steps
            .expand(
              (s) => s.fields.map(
                (f) => _AcroField(
                  name: f.id,
                  label: f.label,
                  type: f.type,
                  page: f.page ?? 1,
                  options: f.options,
                ),
              ),
            )
            .toList();
      }

      final acroPages = acroFields.map((f) => f.page).toSet().toList()..sort();

      // 5. Seed values: first restore from draft (AcroForm names), then autofill.
      final values = Map<String, dynamic>.from(filledForm.fieldValues);
      if (existing == null) {
        await _autofillAcro(values, acroFields, transaction);
      }

      // 6. Build text controllers keyed by AcroForm name.
      final controllers = <String, TextEditingController>{};
      for (final f in acroFields) {
        if (_isTextField(f.type)) {
          controllers[f.name] = TextEditingController(
            text: values[f.name]?.toString() ?? '',
          );
        }
      }

      setState(() {
        _template = template;
        _filledForm = filledForm;
        _acroFields = acroFields;
        _acroPages = acroPages;
        _values.addAll(values);
        _controllers.addAll(controllers);
        _blankPdfBytes = pdfBytes;
        _isLoading = false;
      });

      // Kick off AI label generation in the background if not yet done.
      if (template.fieldLabels.isEmpty && acroFields.isNotEmpty) {
        unawaited(_triggerLabelFetch(template, acroFields));
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── AcroForm extraction ────────────────────────────────────────────────────

  static String _normName(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static String _prettify(String name) {
    return name
        .replaceAll(RegExp('[_.]'), ' ')
        .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  List<_AcroField> _extractAcroFields(
    Uint8List pdfBytes,
    FormTemplate template,
  ) {
    // AI labels from the cloud function take priority, then template step labels, then prettify.
    final normToLabel = <String, String>{};
    for (final step in template.steps) {
      for (final f in step.fields) {
        normToLabel[_normName(f.id)] = f.label;
        normToLabel[_normName(f.label)] = f.label;
      }
    }

    final doc = sf_pdf.PdfDocument(inputBytes: pdfBytes);
    final form = doc.form;
    final result = <_AcroField>[];

    for (int i = 0; i < form.fields.count; i++) {
      final field = form.fields[i];
      final name = field.name ?? '';
      if (name.isEmpty) continue;

      final page = field.page;
      final pageIndex = page != null ? doc.pages.indexOf(page) : 0;
      // AI label (exact name match) → template label → prettified name
      final label =
          template.fieldLabels[name] ??
          normToLabel[_normName(name)] ??
          _prettify(name);

      FormFieldType type = FormFieldType.text;
      final options = <String>[];

      if (field is sf_pdf.PdfCheckBoxField) {
        type = FormFieldType.checkbox;
      } else if (field is sf_pdf.PdfRadioButtonListField) {
        type = FormFieldType.radio;
        for (int j = 0; j < field.items.count; j++) {
          options.add(field.items[j].value);
        }
      } else if (field is sf_pdf.PdfComboBoxField) {
        type = FormFieldType.dropdown;
        for (int j = 0; j < field.items.count; j++) {
          options.add(field.items[j].text);
        }
      } else if (field is sf_pdf.PdfSignatureField) {
        type = FormFieldType.signature;
      }

      final b = field.bounds;
      final pageSize =
          doc.pages[pageIndex < doc.pages.count ? pageIndex : 0].size;

      result.add(
        _AcroField(
          name: name,
          label: label,
          type: type,
          page: pageIndex + 1,
          options: options,
          rawLeft: b.left,
          rawTop: b.top,
          rawWidth: b.width,
          rawHeight: b.height,
          pageWidth: pageSize.width,
          pageHeight: pageSize.height,
        ),
      );
    }

    doc.dispose();
    return result;
  }

  // ── Autofill (AcroForm-aware) ──────────────────────────────────────────────

  Future<void> _autofillAcro(
    Map<String, dynamic> values,
    List<_AcroField> fields,
    tx_model.Transaction? transaction,
  ) async {
    final agent = ref.read(authNotifierProvider);

    // Format closing date once for reuse.
    final closingDateStr = transaction?.closingDate != null
        ? '${transaction!.closingDate!.month.toString().padLeft(2, '0')}/'
              '${transaction.closingDate!.day.toString().padLeft(2, '0')}/'
              '${transaction.closingDate!.year}'
        : null;
    final priceStr = transaction?.purchasePrice != null
        ? transaction!.purchasePrice!.toStringAsFixed(0)
        : null;

    for (final f in fields) {
      if (values.containsKey(f.name)) continue;
      final norm = _normName('${f.name} ${f.label}');

      // Agent
      if ((norm.contains('agentname') || norm.contains('brokername')) &&
          agent.userName.isNotEmpty) {
        values[f.name] = agent.userName;
      } else if ((norm.contains('agentemail') ||
              norm.contains('brokeremail')) &&
          agent.userEmail.isNotEmpty) {
        values[f.name] = agent.userEmail;
      }

      if (transaction == null) {
        continue;
      }
      // Property address
      else if (_matchAny(norm, [
            'streetaddress',
            'propertyaddress',
            'subjectproperty',
          ]) &&
          transaction.propertyAddress.isNotEmpty) {
        values[f.name] = transaction.propertyAddress;
      } else if (norm == 'city' || norm == 'propertycity') {
        values[f.name] = transaction.propertyCity ?? '';
      } else if (norm == 'state' || norm == 'propertystate') {
        values[f.name] = transaction.propertyState ?? '';
      } else if (_matchAny(norm, ['zip', 'zipcode', 'postalcode'])) {
        values[f.name] = transaction.propertyZip ?? '';
      } else if (_matchAny(norm, ['county', 'countyin'])) {
        values[f.name] = transaction.propertyCounty ?? '';
      }
      // Deal terms
      else if (_matchAny(norm, [
            'purchaseprice',
            'saleprice',
            'contractprice',
          ]) &&
          priceStr != null) {
        values[f.name] = priceStr;
      } else if (_matchAny(norm, [
            'closingdate',
            'settlementdate',
            'closdate',
          ]) &&
          closingDateStr != null) {
        values[f.name] = closingDateStr;
      }
      // Seller
      else if (_matchAny(norm, ['seller', 'sellername', 'grantor']) &&
          !norm.contains('broker') &&
          transaction.sellerName != null) {
        values[f.name] = transaction.sellerName!;
      }
      // Today's date (contract date)
      else if (norm == 'date' ||
          norm == 'contractdate' ||
          norm == 'agreementdate') {
        final now = DateTime.now();
        values[f.name] =
            '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
      }
    }

    // Buyer contact info
    if (transaction != null &&
        transaction.buyerContactId != null &&
        transaction.buyerContactId!.isNotEmpty) {
      final buyer = await fetchContact(transaction.buyerContactId!);
      if (buyer != null) {
        for (final f in fields) {
          if (values.containsKey(f.name)) continue;
          final norm = _normName('${f.name} ${f.label}');
          final isBuyer =
              norm.contains('buyer') ||
              norm.contains('purchaser') ||
              norm.contains('client');
          if (!isBuyer) continue;

          if (norm.contains('firstname') || norm.contains('first')) {
            values[f.name] = buyer.firstName;
          } else if (norm.contains('lastname') || norm.contains('last')) {
            values[f.name] = buyer.lastName;
          } else if (norm.contains('email')) {
            values[f.name] = buyer.email ?? '';
          } else if (norm.contains('phone')) {
            values[f.name] = buyer.phone ?? '';
          } else if (norm.contains('address')) {
            values[f.name] = buyer.fullAddress ?? '';
          } else if (norm.contains('name')) {
            values[f.name] = buyer.fullName;
          }
        }
      }
    }
  }

  static bool _matchAny(String norm, List<String> keywords) =>
      keywords.any(norm.contains);

  // ── Live preview (on blur) ─────────────────────────────────────────────────

  void _updatePreviewNow() {
    final blank = _blankPdfBytes;
    if (blank == null) return;
    try {
      final stamped = PdfStamper.stamp(blank, _values);
      setState(() {
        _previewPdfBytes = stamped;
        _previewVersion++;
      });
    } catch (_) {
      // Ignore stamp errors during preview; final generation will surface them.
    }
  }

  // ── AI label fetch (background) ────────────────────────────────────────────

  Future<void> _triggerLabelFetch(
    FormTemplate template,
    List<_AcroField> fields,
  ) async {
    if (fields.isEmpty) return;
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('labelFormFields');
      await fn.call({
        'templateId': template.id,
        'boardId': template.boardId,
        'fieldNames': fields.map((f) => f.name).toList(),
      });
      // Labels are now stored in Firestore; they'll be used on the next open.
    } catch (e) {
      debugPrint('Failed to trigger label fetch: $e');
      // Non-fatal — pretty-printed names are still shown.
    }
  }

  Future<FilledForm> _createDraft({
    required String txId,
    required FormTemplate template,
  }) async {
    // Standalone fills (no transaction) are in-memory only — no Firestore write
    // because the filled_forms subcollection rule requires a parent transaction
    // document, which doesn't exist for the standalone path.
    if (txId == 'new') {
      return FilledForm(
        id: 'standalone-${DateTime.now().millisecondsSinceEpoch}',
        transactionId: 'standalone',
        templateId: template.id,
        templateName: template.name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    final formId = await createFilledForm(
      txId: txId,
      templateId: template.id,
      templateName: template.name,
    );
    return FilledForm(
      id: formId,
      transactionId: txId,
      templateId: template.id,
      templateName: template.name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
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

  void _onFieldBlur(String fieldId, value) {
    // Update the value synchronously (in case onChanged hasn't fired yet for
    // selection widgets), then stamp a fresh preview.
    _values[fieldId] = value;
    _updatePreviewNow();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    final form = _filledForm;
    if (form == null || form.transactionId == 'standalone') return;
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

  int _pageForStep(int step) {
    if (_acroPages.isNotEmpty && step < _acroPages.length) {
      return _acroPages[step];
    }
    final steps = _template?.steps;
    if (steps == null || step >= steps.length) return step + 1;
    final fields = steps[step].fields;
    return fields.isNotEmpty ? (fields.first.page ?? step + 1) : step + 1;
  }

  void _jumpPdfToStep(int step) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pdfController.jumpToPage(_pageForStep(step));
    });
  }

  int get _stepCount => _acroPages.isNotEmpty
      ? _acroPages.length
      : (_template?.steps.length ?? 1);

  void _next() {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      _jumpPdfToStep(_step);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _jumpPdfToStep(_step);
    }
  }

  // ── PDF generation ─────────────────────────────────────────────────────────

  Future<void> _generatePdf() async {
    final template = _template;
    final form = _filledForm;
    final agent = ref.read(agentProfileProvider).value;
    if (template == null || form == null) return;

    setState(() => _isGenerating = true);
    try {
      // Use cached blank PDF (already downloaded at init) or re-download.
      final pdfBytes =
          _blankPdfBytes ??
          await StorageService.downloadTemplate(
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

      // Mark FilledForm as complete (skip for standalone — no parent tx doc).
      if (form.transactionId != 'standalone') {
        await completeFilledForm(form.transactionId, form.id, storagePath);
      }

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

  // ── Remote signing request ─────────────────────────────────────────────────

  Future<void> _requestSigningFromWizard() async {
    final template = _template;
    final form = _filledForm;
    if (template == null || form == null || widget.txId == 'new') return;

    setState(() => _isRequestingSigning = true);
    try {
      _saveTimer?.cancel();
      await _save();

      final auth = ref.read(authNotifierProvider);
      final agent = ref.read(agentProfileProvider).value;
      final agentId = auth.currentUser!.uid;
      final boardId = agent?.boardId ?? agentId;

      final sigFieldIds = template.steps
          .expand((s) => s.fields)
          .where((f) => f.type == FormFieldType.signature)
          .map((f) => f.id)
          .toList();

      final fieldValues = Map<String, dynamic>.from(_values)
        ..removeWhere((_, v) => v is List<int>);

      final now = DateTime.now();
      final request = SigningRequest(
        token: '',
        agentId: agentId,
        transactionId: widget.txId,
        filledFormId: form.id,
        templateId: template.id,
        templateName: template.name,
        boardId: boardId,
        fieldValues: fieldValues,
        signatureFieldIds: sigFieldIds,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );

      final token = await createSigningRequest(request);
      final url = 'https://formtract.web.app/sign/$token';

      if (!mounted) return;
      _showSigningLinkSheet(url, token, template.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create signing request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRequestingSigning = false);
    }
  }

  void _showSigningLinkSheet(String url, String token, String templateName) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) =>
          _SigningLinkSheet(url: url, token: token, templateName: templateName),
    );
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
    final useAcro = _acroPages.isNotEmpty;
    final stepCount = _stepCount;
    final isLastStep = _step == stepCount - 1;

    final currentPageNum = _pageForStep(_step);
    final stepTitle = 'Page $currentPageNum';
    final currentPageFields = useAcro
        ? _acroFields.where((f) => f.page == currentPageNum).toList()
        : <_AcroField>[];

    final appBar = AppBar(
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
            '${_step + 1} of $stepCount — $stepTitle',
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
    );

    Widget stepBody;
    if (useAcro) {
      stepBody = _AcroStepView(
        pageNum: currentPageNum,
        fields: currentPageFields,
        values: _values,
        controllers: _controllers,
        onChanged: _onFieldChanged,
        onFocus: (_) {},
        onBlur: _onFieldBlur,
      );
    } else {
      // Fallback: no AcroForm fields — use template steps.
      final currentStep = template.steps[_step];
      stepBody = _FormStepView(
        step: currentStep,
        values: _values,
        controllers: _controllers,
        onChanged: _onFieldChanged,
      );
    }

    final formPanel = Column(
      children: [
        _StepProgressBar(current: _step, total: stepCount),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: stepBody,
          ),
        ),
        _BottomBar(
          isFirst: _step == 0,
          isLast: isLastStep,
          isGenerating: _isGenerating,
          isRequestingSigning: _isRequestingSigning,
          onBack: _back,
          onNext: _next,
          onGenerate: _generatePdf,
          onRequestSigning: widget.txId != 'new'
              ? _requestSigningFromWizard
              : null,
        ),
      ],
    );

    final displayPdfBytes = _previewPdfBytes ?? _blankPdfBytes;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800 && displayPdfBytes != null;

        if (isWide) {
          return Scaffold(
            backgroundColor: kBgPage,
            appBar: appBar,
            body: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFF334155),
                    child: SfPdfViewer.memory(
                      displayPdfBytes,
                      key: ValueKey(_previewVersion),
                      controller: _pdfController,
                      pageLayoutMode: PdfPageLayoutMode.single,
                      enableDoubleTapZooming: false,
                      canShowScrollHead: false,
                      canShowScrollStatus: false,
                      canShowPageLoadingIndicator: false,
                      pageSpacing: 0,
                      interactionMode: PdfInteractionMode.pan,
                    ),
                  ),
                ),
                Container(width: 1, color: const Color(0xFFE2E8F0)),
                SizedBox(width: 400, child: formPanel),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: kBgPage,
          appBar: appBar,
          body: formPanel,
        );
      },
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

class _AcroStepView extends StatelessWidget {
  final int pageNum;
  final List<_AcroField> fields;
  final Map<String, dynamic> values;
  final Map<String, TextEditingController> controllers;
  // ignore: avoid_annotating_with_dynamic
  final void Function(String name, dynamic value) onChanged;
  final void Function(String name) onFocus;
  // ignore: avoid_annotating_with_dynamic
  final void Function(String name, dynamic value) onBlur;

  const _AcroStepView({
    required this.pageNum,
    required this.fields,
    required this.values,
    required this.controllers,
    required this.onChanged,
    required this.onFocus,
    required this.onBlur,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Page $pageNum',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${fields.length} field${fields.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            ...fields.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _AcroFieldWidget(
                  field: f,
                  value: values[f.name],
                  controller: controllers[f.name],
                  onChanged: (v) => onChanged(f.name, v),
                  onFocus: () => onFocus(f.name),
                  onBlur: (v) => onBlur(f.name, v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcroFieldWidget extends StatelessWidget {
  final _AcroField field;
  final dynamic value;
  final TextEditingController? controller;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onFocus;
  // ignore: avoid_annotating_with_dynamic
  final void Function(dynamic value) onBlur;

  const _AcroFieldWidget({
    required this.field,
    required this.value,
    required this.controller,
    required this.onChanged,
    required this.onFocus,
    required this.onBlur,
  });

  @override
  Widget build(BuildContext context) {
    Widget w = switch (field.type) {
      FormFieldType.checkbox => _CheckboxField(
        label: field.label,
        value: value == true || value.toString() == 'true',
        onChanged: (v) {
          onChanged(v);
          onBlur(v);
        },
      ),
      FormFieldType.radio => _RadioField(
        label: field.label,
        options: field.options,
        value: value?.toString(),
        onChanged: (v) {
          onChanged(v);
          onBlur(v);
        },
      ),
      FormFieldType.signature => _SignaturePad(
        label: field.label,
        onChanged: onChanged,
      ),
      FormFieldType.dropdown => _DropdownField(
        label: field.label,
        options: field.options,
        value: value?.toString(),
        onChanged: (v) {
          onChanged(v);
          onBlur(v);
        },
      ),
      _ => _TextField(
        label: field.label,
        type: field.type,
        controller: controller ?? TextEditingController(),
        onChanged: onChanged,
        onFocus: onFocus,
        onBlur: () => onBlur(controller?.text ?? ''),
      ),
    };
    // For non-text fields wrap in a tap detector to fire onFocus.
    if (field.type == FormFieldType.checkbox ||
        field.type == FormFieldType.radio ||
        field.type == FormFieldType.dropdown) {
      w = GestureDetector(
        onTap: onFocus,
        behavior: HitTestBehavior.translucent,
        child: w,
      );
    }
    return w;
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
  final VoidCallback? onFocus;
  final VoidCallback? onBlur;

  const _TextField({
    required this.label,
    required this.type,
    required this.controller,
    required this.onChanged,
    this.onFocus,
    this.onBlur,
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
      onTap: onFocus,
      onEditingComplete: onBlur,
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: kBlueAccent),
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
  final bool isRequestingSigning;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onGenerate;
  final VoidCallback? onRequestSigning;

  const _BottomBar({
    required this.isFirst,
    required this.isLast,
    required this.isGenerating,
    required this.isRequestingSigning,
    required this.onBack,
    required this.onNext,
    required this.onGenerate,
    this.onRequestSigning,
  });

  @override
  Widget build(BuildContext context) {
    final busy = isGenerating || isRequestingSigning;
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
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 44)),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (isLast) ...[
            if (onRequestSigning != null) ...[
              OutlinedButton.icon(
                onPressed: busy ? null : onRequestSigning,
                icon: isRequestingSigning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.draw_outlined, size: 16),
                label: const Text('Request Signature'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: busy ? null : onGenerate,
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
              style: FilledButton.styleFrom(minimumSize: const Size(148, 44)),
            ),
          ] else
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

// ── Signing link bottom sheet ─────────────────────────────────────────────────

class _SigningLinkSheet extends StatefulWidget {
  final String url;
  final String token;
  final String templateName;
  const _SigningLinkSheet({
    required this.url,
    required this.token,
    required this.templateName,
  });

  @override
  State<_SigningLinkSheet> createState() => _SigningLinkSheetState();
}

class _SigningLinkSheetState extends State<_SigningLinkSheet> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _sendError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signing link copied.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _sendViaFunction() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('sendSigningEmail');
      await fn.call({
        'token': widget.token,
        'clientEmail': email,
        if (_nameCtrl.text.trim().isNotEmpty)
          'clientName': _nameCtrl.text.trim(),
      });
      setState(() => _sent = true);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _sendError = e.message ?? 'Failed to send email.');
    } catch (e) {
      setState(() => _sendError = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kSuccessGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: kSuccessGreen, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signing link created',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Expires in 7 days',
                      style: TextStyle(color: kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // URL display + copy
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kBgPage,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.url,
                    style: const TextStyle(fontSize: 11, color: kTextSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _copy,
                  child: const Icon(Icons.copy, size: 16, color: kBlueAccent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // Send via email section
          Text(
            'Send to client via email',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          if (_sent)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kSuccessGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: kSuccessGreen,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Email sent to ${_emailCtrl.text.trim()}',
                    style: const TextStyle(color: kSuccessGreen, fontSize: 13),
                  ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Client name (optional)',
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Client email',
                isDense: true,
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
            if (_sendError != null) ...[
              const SizedBox(height: 8),
              Text(
                _sendError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _sendViaFunction,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 16),
                label: const Text('Send Signing Email'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
          ],
          const SizedBox(height: 8),
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

  Future<void> _openPdf() async {
    final uri = Uri.parse(pdfUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: pdfUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _emailPdf(BuildContext context) async {
    final subject = Uri.encodeComponent('$templateName — Formtract');
    final body = Uri.encodeComponent(
      'Please find the completed form at the link below:\n\n$pdfUrl',
    );
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No email app available.')));
    }
  }

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
              SizedBox(
                width: 240,
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openPdf,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open PDF'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _emailPdf(context),
                        icon: const Icon(Icons.email_outlined, size: 18),
                        label: const Text('Email PDF'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _copyLink(context),
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('Copy Link'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(onPressed: onClose, child: const Text('Done')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
