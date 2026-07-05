import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/services/pdf_field_extractor.dart';
import 'package:formtract/core/services/storage_service.dart';

/// Creates and manages [FormTemplate] records in Firestore, backed by PDFs in
/// Firebase Storage.
class TemplateService {
  static final _db = FirebaseFirestore.instance;

  /// Uploads a PDF, extracts its AcroForm schema, and writes a [FormTemplate]
  /// document to Firestore. Returns the saved template (with its Firestore id).
  static Future<FormTemplate> uploadTemplate({
    required Uint8List pdfBytes,
    required String name,
    required String boardId,
    String? category,
    String? description,
  }) async {
    // Pre-allocate a Firestore document id so we can use it as the Storage key.
    final docRef = _db.collection('form_templates').doc();
    final templateId = docRef.id;

    // Extract schema from the PDF's AcroForm fields.
    final steps = PdfFieldExtractor.extractSteps(pdfBytes);

    // Upload PDF to Firebase Storage.
    final storagePath = await StorageService.uploadTemplate(
      pdfBytes: pdfBytes,
      boardId: boardId,
      templateId: templateId,
    );

    final now = DateTime.now();
    final template = FormTemplate(
      id: templateId,
      boardId: boardId,
      name: name,
      description: description,
      category: category,
      pdfStoragePath: storagePath,
      steps: steps,
      schemaReady: steps.isNotEmpty,
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(template.toFirestore());
    return template;
  }

  /// Seeds the four test PDFs bundled in assets into Storage + Firestore.
  /// Only call this once per board — checks for existing templates first.
  static Future<int> seedTestTemplates(String boardId) async {
    final existing = await _db
        .collection('form_templates')
        .where('boardId', isEqualTo: boardId)
        .get();
    if (existing.docs.isNotEmpty) return 0; // already seeded

    const seeds = [
      (
        'assets/test_pdfs/colorado_bc60.pdf',
        'Colorado BC-60 Buyer Agency',
        'Buyer Agreements',
      ),
      (
        'assets/test_pdfs/louisiana_buyer_rep.pdf',
        'Louisiana Buyer Representation',
        'Buyer Agreements',
      ),
      (
        'assets/test_pdfs/oklahoma_buyer_broker.pdf',
        'Oklahoma Buyer Broker',
        'Buyer Agreements',
      ),
      (
        'assets/test_pdfs/wisconsin_wb36.pdf',
        'Wisconsin WB-36 Buyer Agency',
        'Buyer Agreements',
      ),
    ];

    int count = 0;
    for (final (assetPath, name, category) in seeds) {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      await uploadTemplate(
        pdfBytes: bytes,
        name: name,
        boardId: boardId,
        category: category,
      );
      count++;
    }
    return count;
  }

  static Future<void> deleteTemplate(String templateId) async {
    await _db.collection('form_templates').doc(templateId).delete();
  }
}
