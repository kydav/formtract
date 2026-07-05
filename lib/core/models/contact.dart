import 'package:cloud_firestore/cloud_firestore.dart';

class Contact {
  final String id;
  final String agentId;
  final String boardId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? state;
  final String? zip;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Contact({
    required this.id,
    required this.agentId,
    required this.boardId,
    required this.firstName,
    required this.lastName,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.zip,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase();
  }

  String? get fullAddress {
    final parts = [
      address,
      city,
      state,
      zip,
    ].where((p) => p?.isNotEmpty ?? false);
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory Contact.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return Contact(
      id: doc.id,
      agentId: d['agentId'] as String,
      boardId: d['boardId'] as String,
      firstName: d['firstName'] as String? ?? '',
      lastName: d['lastName'] as String? ?? '',
      email: d['email'] as String?,
      phone: d['phone'] as String?,
      address: d['address'] as String?,
      city: d['city'] as String?,
      state: d['state'] as String?,
      zip: d['zip'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'agentId': agentId,
    'boardId': boardId,
    'firstName': firstName,
    'lastName': lastName,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (address != null) 'address': address,
    if (city != null) 'city': city,
    if (state != null) 'state': state,
    if (zip != null) 'zip': zip,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
