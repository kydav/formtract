import 'package:cloud_firestore/cloud_firestore.dart';

enum FormFieldType {
  text,
  email,
  phone,
  date,
  checkbox,
  radio,
  dropdown,
  signature,
  initials,
  number,
}

class FormFieldDef {
  final String id; // matches AcroForm field name in PDF
  final String label;
  final FormFieldType type;
  final bool required;
  final List<String> options; // for radio / dropdown

  // Position on the PDF page — null for manually-created / AcroForm templates.
  final int? page;       // 1-indexed page number
  final double? x;       // % of page width (0-100)
  final double? y;       // % of page height (0-100)
  final double? width;   // % of page width
  final double? height;  // % of page height

  // Maps this field to a known contact/property value for autofill.
  // E.g. "buyer.fullName", "agent.email", "property.address"
  final String? contactMapping;

  bool get hasPosition => page != null && x != null && y != null;

  const FormFieldDef({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
    this.page,
    this.x,
    this.y,
    this.width,
    this.height,
    this.contactMapping,
  });

  FormFieldDef copyWith({
    String? id,
    String? label,
    FormFieldType? type,
    bool? required,
    List<String>? options,
    int? page,
    double? x,
    double? y,
    double? width,
    double? height,
    String? contactMapping,
    bool clearContactMapping = false,
  }) => FormFieldDef(
    id: id ?? this.id,
    label: label ?? this.label,
    type: type ?? this.type,
    required: required ?? this.required,
    options: options ?? this.options,
    page: page ?? this.page,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    contactMapping: clearContactMapping ? null : (contactMapping ?? this.contactMapping),
  );

  factory FormFieldDef.fromMap(Map<String, dynamic> m) => FormFieldDef(
    id: m['id'] as String,
    label: m['label'] as String,
    type: FormFieldType.values.firstWhere(
      (t) => t.name == (m['type'] as String? ?? 'text'),
      orElse: () => FormFieldType.text,
    ),
    required: m['required'] as bool? ?? false,
    options: List<String>.from(m['options'] as List? ?? []),
    page: (m['page'] as num?)?.toInt(),
    x: (m['x'] as num?)?.toDouble(),
    y: (m['y'] as num?)?.toDouble(),
    width: (m['width'] as num?)?.toDouble(),
    height: (m['height'] as num?)?.toDouble(),
    contactMapping: m['contactMapping'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'type': type.name,
    'required': required,
    if (options.isNotEmpty) 'options': options,
    if (page != null) 'page': page,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (contactMapping != null) 'contactMapping': contactMapping,
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
  // AI-generated labels keyed by AcroForm field name (populated by labelFormFields function).
  final Map<String, String> fieldLabels;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FormTemplate({
    required this.id,
    required this.boardId,
    required this.name,
    required this.pdfStoragePath,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.category,
    this.steps = const [],
    this.schemaReady = false,
    this.fieldLabels = const {},
  });

  factory FormTemplate.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    final rawLabels = d['fieldLabels'] as Map<String, dynamic>?;
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
      fieldLabels: rawLabels != null
          ? rawLabels.map((k, v) => MapEntry(k, v as String))
          : const {},
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
    if (fieldLabels.isNotEmpty) 'fieldLabels': fieldLabels,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
