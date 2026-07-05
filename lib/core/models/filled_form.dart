import 'package:cloud_firestore/cloud_firestore.dart';

enum FilledFormStatus { draft, complete, signed }

class FilledForm {
  final String id;
  final String transactionId;
  final String templateId;
  final String templateName;
  final Map<String, dynamic> fieldValues; // pdfFieldId → value
  final FilledFormStatus status;
  final String? pdfStoragePath; // Firebase Storage path of stamped PDF
  final DateTime createdAt;
  final DateTime updatedAt;

  const FilledForm({
    required this.id,
    required this.transactionId,
    required this.templateId,
    required this.templateName,
    this.fieldValues = const {},
    this.status = FilledFormStatus.draft,
    this.pdfStoragePath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FilledForm.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FilledForm(
      id: doc.id,
      transactionId: d['transactionId'] as String,
      templateId: d['templateId'] as String,
      templateName: d['templateName'] as String? ?? '',
      fieldValues: Map<String, dynamic>.from(d['fieldValues'] as Map? ?? {}),
      status: FilledFormStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String? ?? 'draft'),
        orElse: () => FilledFormStatus.draft,
      ),
      pdfStoragePath: d['pdfStoragePath'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'transactionId': transactionId,
    'templateId': templateId,
    'templateName': templateName,
    'fieldValues': fieldValues,
    'status': status.name,
    if (pdfStoragePath != null) 'pdfStoragePath': pdfStoragePath,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
