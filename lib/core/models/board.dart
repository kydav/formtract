import 'package:cloud_firestore/cloud_firestore.dart';

class Board {
  final String id;
  final String name;
  final String state;
  final String? contactEmail;
  final String? phone;
  final String? website;
  final DateTime createdAt;

  const Board({
    required this.id,
    required this.name,
    required this.state,
    this.contactEmail,
    this.phone,
    this.website,
    required this.createdAt,
  });

  factory Board.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Board(
      id: doc.id,
      name: d['name'] as String,
      state: d['state'] as String? ?? 'UT',
      contactEmail: d['contactEmail'] as String?,
      phone: d['phone'] as String?,
      website: d['website'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'state': state,
    if (contactEmail != null) 'contactEmail': contactEmail,
    if (phone != null) 'phone': phone,
    if (website != null) 'website': website,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
