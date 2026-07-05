import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus { draft, inProgress, awaitingSignature, complete }

extension TransactionStatusLabel on TransactionStatus {
  String get label => switch (this) {
    TransactionStatus.draft             => 'Draft',
    TransactionStatus.inProgress        => 'In Progress',
    TransactionStatus.awaitingSignature => 'Awaiting Signature',
    TransactionStatus.complete          => 'Complete',
  };
}

class Transaction {
  final String id;
  final String agentId;
  final String boardId;
  final String? buyerContactId;
  final String? sellerContactId;
  final String propertyAddress;
  final String? propertyCity;
  final String? propertyState;
  final String? propertyZip;
  final TransactionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Transaction({
    required this.id,
    required this.agentId,
    required this.boardId,
    this.buyerContactId,
    this.sellerContactId,
    required this.propertyAddress,
    this.propertyCity,
    this.propertyState,
    this.propertyZip,
    this.status = TransactionStatus.draft,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullAddress {
    final parts = [propertyAddress, propertyCity, propertyState, propertyZip]
        .where((p) => p?.isNotEmpty ?? false);
    return parts.join(', ');
  }

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Transaction(
      id: doc.id,
      agentId: d['agentId'] as String,
      boardId: d['boardId'] as String,
      buyerContactId: d['buyerContactId'] as String?,
      sellerContactId: d['sellerContactId'] as String?,
      propertyAddress: d['propertyAddress'] as String? ?? '',
      propertyCity: d['propertyCity'] as String?,
      propertyState: d['propertyState'] as String?,
      propertyZip: d['propertyZip'] as String?,
      status: TransactionStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String? ?? 'draft'),
        orElse: () => TransactionStatus.draft,
      ),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'agentId': agentId,
    'boardId': boardId,
    if (buyerContactId != null) 'buyerContactId': buyerContactId,
    if (sellerContactId != null) 'sellerContactId': sellerContactId,
    'propertyAddress': propertyAddress,
    if (propertyCity != null) 'propertyCity': propertyCity,
    if (propertyState != null) 'propertyState': propertyState,
    if (propertyZip != null) 'propertyZip': propertyZip,
    'status': status.name,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Transaction copyWith({TransactionStatus? status}) => Transaction(
    id: id,
    agentId: agentId,
    boardId: boardId,
    buyerContactId: buyerContactId,
    sellerContactId: sellerContactId,
    propertyAddress: propertyAddress,
    propertyCity: propertyCity,
    propertyState: propertyState,
    propertyZip: propertyZip,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}
