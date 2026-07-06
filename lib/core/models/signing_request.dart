import 'package:cloud_firestore/cloud_firestore.dart';

enum SigningRequestStatus { pending, signed, expired }

class SigningRequest {
  final String token; // document ID
  final String agentId;
  final String transactionId;
  final String filledFormId;
  final String templateId;
  final String templateName;
  final String boardId;
  final Map<String, dynamic> fieldValues; // non-signature values only
  final List<String> signatureFieldIds;
  final SigningRequestStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? signedAt;
  final String? signedPdfStoragePath;

  const SigningRequest({
    required this.token,
    required this.agentId,
    required this.transactionId,
    required this.filledFormId,
    required this.templateId,
    required this.templateName,
    required this.boardId,
    required this.fieldValues,
    required this.signatureFieldIds,
    required this.createdAt,
    required this.expiresAt,
    this.status = SigningRequestStatus.pending,
    this.signedAt,
    this.signedPdfStoragePath,
  });

  bool get isExpired =>
      status == SigningRequestStatus.expired ||
      DateTime.now().isAfter(expiresAt);

  bool get isSigned => status == SigningRequestStatus.signed;

  String get signingUrl => 'https://formtract.web.app/sign/$token';

  factory SigningRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return SigningRequest(
      token: doc.id,
      agentId: d['agentId'] as String,
      transactionId: d['transactionId'] as String,
      filledFormId: d['filledFormId'] as String,
      templateId: d['templateId'] as String,
      templateName: d['templateName'] as String,
      boardId: d['boardId'] as String,
      fieldValues: Map<String, dynamic>.from(d['fieldValues'] as Map? ?? {}),
      signatureFieldIds: List<String>.from(d['signatureFieldIds'] as List? ?? []),
      status: SigningRequestStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String? ?? 'pending'),
        orElse: () => SigningRequestStatus.pending,
      ),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 7)),
      signedAt: (d['signedAt'] as Timestamp?)?.toDate(),
      signedPdfStoragePath: d['signedPdfStoragePath'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'agentId': agentId,
        'transactionId': transactionId,
        'filledFormId': filledFormId,
        'templateId': templateId,
        'templateName': templateName,
        'boardId': boardId,
        'fieldValues': fieldValues,
        'signatureFieldIds': signatureFieldIds,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        if (signedAt != null) 'signedAt': Timestamp.fromDate(signedAt!),
        if (signedPdfStoragePath != null)
          'signedPdfStoragePath': signedPdfStoragePath,
      };
}
