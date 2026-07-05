import 'package:cloud_firestore/cloud_firestore.dart';

enum FormFieldType { text, email, phone, date, checkbox, radio, dropdown, signature, initials, number }

class FormFieldDef {
  final String id; // matches AcroForm field name in PDF
  final String label;
  final FormFieldType type;
  final bool required;
  final List<String> options; // for radio / dropdown

  const FormFieldDef({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
  });

  factory FormFieldDef.fromMap(Map<String, dynamic> m) => FormFieldDef(
    id: m['id'] as String,
    label: m['label'] as String,
    type: FormFieldType.values.firstWhere(
      (t) => t.name == (m['type'] as String? ?? 'text'),
      orElse: () => FormFieldType.text,
    ),
    required: m['required'] as bool? ?? false,
    options: List<String>.from(m['options'] as List? ?? []),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'type': type.name,
    'required': required,
    if (options.isNotEmpty) 'options': options,
  };
}

class FormStep {
  final String title;
  final List<FormFieldDef> fields;

  const FormStep({required this.title, required this.fields});

  factory FormStep.fromMap(Map<String, dynamic> m) => FormStep(
    title: m['title'] as String,
    fields: (m['fields'] as List? ?? [])
        .map((f) => FormFieldDef.fromMap(f as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'fields': fields.map((f) => f.toMap()).toList(),
  };
}

class FormTemplate {
  final String id;
  final String boardId;
  final String name;
  final String? description;
  final String? category; // e.g. "Buyer Agreements", "Listing", "Purchase"
  final String pdfStoragePath; // original PDF in Firebase Storage
  final List<FormStep> steps; // AI-parsed schema
  final bool schemaReady; // false until AI parsing completes
  final DateTime createdAt;
  final DateTime updatedAt;

  const FormTemplate({
    required this.id,
    required this.boardId,
    required this.name,
    this.description,
    this.category,
    required this.pdfStoragePath,
    this.steps = const [],
    this.schemaReady = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FormTemplate.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FormTemplate(
      id: doc.id,
      boardId: d['boardId'] as String,
      name: d['name'] as String,
      description: d['description'] as String?,
      category: d['category'] as String?,
      pdfStoragePath: d['pdfStoragePath'] as String? ?? '',
      steps: (d['steps'] as List? ?? [])
          .map((s) => FormStep.fromMap(s as Map<String, dynamic>))
          .toList(),
      schemaReady: d['schemaReady'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'boardId': boardId,
    'name': name,
    if (description != null) 'description': description,
    if (category != null) 'category': category,
    'pdfStoragePath': pdfStoragePath,
    'steps': steps.map((s) => s.toMap()).toList(),
    'schemaReady': schemaReady,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
