import 'package:cloud_firestore/cloud_firestore.dart';

enum AgentRole { agent, admin }

class Agent {
  final String id; // = Firebase Auth uid
  final String boardId;
  final String email;
  final String firstName;
  final String lastName;
  final String? licenseNumber;
  final AgentRole role;
  final DateTime createdAt;

  const Agent({
    required this.id,
    required this.boardId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.createdAt,
    this.licenseNumber,
    this.role = AgentRole.agent,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase().isNotEmpty
        ? '$f$l'.toUpperCase()
        : email[0].toUpperCase();
  }

  factory Agent.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return Agent(
      id: doc.id,
      boardId: d['boardId'] as String,
      email: d['email'] as String,
      firstName: d['firstName'] as String? ?? '',
      lastName: d['lastName'] as String? ?? '',
      licenseNumber: d['licenseNumber'] as String?,
      role: AgentRole.values.firstWhere(
        (r) => r.name == (d['role'] as String? ?? 'agent'),
        orElse: () => AgentRole.agent,
      ),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'boardId': boardId,
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    if (licenseNumber != null) 'licenseNumber': licenseNumber,
    'role': role.name,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  Agent copyWith({
    String? firstName,
    String? lastName,
    String? licenseNumber,
    AgentRole? role,
  }) => Agent(
    id: id,
    boardId: boardId,
    email: email,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    licenseNumber: licenseNumber ?? this.licenseNumber,
    role: role ?? this.role,
    createdAt: createdAt,
  );
}
