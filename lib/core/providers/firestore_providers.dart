import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/agent.dart';
import 'package:formtract/core/models/contact.dart';
import 'package:formtract/core/models/filled_form.dart';
import 'package:formtract/core/models/form_template.dart';
import 'package:formtract/core/models/signing_request.dart';
import 'package:formtract/core/models/transaction.dart' as tx_model;
import 'package:formtract/core/providers/auth_provider.dart';

final _db = FirebaseFirestore.instance;

// ─── Agent profile ────────────────────────────────────────────────────────────

/// Current agent's Firestore profile document.
/// Auto-creates the document on first access so the profile always exists.
final agentProfileProvider = StreamProvider<Agent?>((ref) {
  final auth = ref.watch(authNotifierProvider);
  if (!auth.isLoggedIn) return Stream.value(null);

  final uid = auth.currentUser!.uid;
  final email = auth.userEmail;

  return _db.collection('agents').doc(uid).snapshots().asyncMap((snap) async {
    if (!snap.exists) {
      await _db.collection('agents').doc(uid).set({
        'boardId': uid,
        'email': email,
        'firstName': '',
        'lastName': '',
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    }
    return Agent.fromFirestore(snap);
  });
});

/// Creates an agent profile if one doesn't exist yet (called after first sign-up).
Future<void> ensureAgentProfile({
  required String uid,
  required String email,
  required String boardId,
}) async {
  final ref = _db.collection('agents').doc(uid);
  final snap = await ref.get();
  if (!snap.exists) {
    final now = DateTime.now();
    await ref.set(
      Agent(
        id: uid,
        boardId: boardId,
        email: email,
        firstName: '',
        lastName: '',
        createdAt: now,
      ).toFirestore(),
    );
  }
}

// ─── Transactions ─────────────────────────────────────────────────────────────

/// All transactions for the current agent, ordered newest first.
final transactionsProvider = StreamProvider<List<tx_model.Transaction>>((ref) {
  final auth = ref.watch(authNotifierProvider);
  if (!auth.isLoggedIn) return Stream.value([]);
  return _db
      .collection('transactions')
      .where('agentId', isEqualTo: auth.currentUser!.uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(tx_model.Transaction.fromFirestore).toList());
});

/// A single transaction by ID.
final transactionByIdProvider =
    StreamProvider.family<tx_model.Transaction?, String>((ref, txId) {
      return _db
          .collection('transactions')
          .doc(txId)
          .snapshots()
          .map((s) => s.exists ? tx_model.Transaction.fromFirestore(s) : null);
    });

Future<String> createTransaction(tx_model.Transaction transaction) async {
  final ref = await _db
      .collection('transactions')
      .add(transaction.toFirestore());
  return ref.id;
}

Future<void> updateTransactionStatus(
  String txId,
  tx_model.TransactionStatus status,
) async {
  await _db.collection('transactions').doc(txId).update({
    'status': status.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> updateTransactionContact(
  String txId, {
  String? buyerContactId,
}) async {
  await _db.collection('transactions').doc(txId).update({
    'buyerContactId': ?buyerContactId,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> deleteTransaction(String txId) async {
  await _db.collection('transactions').doc(txId).delete();
}

// ─── Contacts ─────────────────────────────────────────────────────────────────

/// All contacts for the current agent, ordered by last name.
final contactsProvider = StreamProvider<List<Contact>>((ref) {
  final auth = ref.watch(authNotifierProvider);
  if (!auth.isLoggedIn) return Stream.value([]);
  return _db
      .collection('contacts')
      .where('agentId', isEqualTo: auth.currentUser!.uid)
      .orderBy('lastName')
      .snapshots()
      .map((s) => s.docs.map(Contact.fromFirestore).toList());
});

/// A single contact by ID.
final contactByIdProvider = StreamProvider.family<Contact?, String>((
  ref,
  contactId,
) {
  if (contactId.isEmpty) return Stream.value(null);
  return _db
      .collection('contacts')
      .doc(contactId)
      .snapshots()
      .map((s) => s.exists ? Contact.fromFirestore(s) : null);
});

Future<String> createContact(Contact contact) async {
  final ref = await _db.collection('contacts').add(contact.toFirestore());
  return ref.id;
}

Future<void> updateContact(Contact contact) async {
  await _db
      .collection('contacts')
      .doc(contact.id)
      .update(contact.toFirestore());
}

Future<void> deleteContact(String contactId) async {
  await _db.collection('contacts').doc(contactId).delete();
}

// ─── Form templates ───────────────────────────────────────────────────────────

/// All form templates for a given board.
final formTemplatesProvider = StreamProvider.family<List<FormTemplate>, String>(
  (ref, boardId) {
    return _db
        .collection('form_templates')
        .where('boardId', isEqualTo: boardId)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(FormTemplate.fromFirestore).toList());
  },
);

/// A single template by id.
final formTemplateByIdProvider = StreamProvider.family<FormTemplate?, String>((
  ref,
  templateId,
) {
  return _db
      .collection('form_templates')
      .doc(templateId)
      .snapshots()
      .map((s) => s.exists ? FormTemplate.fromFirestore(s) : null);
});

// ─── Filled forms ─────────────────────────────────────────────────────────────

/// All filled forms for a transaction, newest first.
final filledFormsProvider = StreamProvider.family<List<FilledForm>, String>((
  ref,
  txId,
) {
  return _db
      .collection('transactions')
      .doc(txId)
      .collection('filled_forms')
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(FilledForm.fromFirestore).toList());
});

Future<String> createFilledForm({
  required String txId,
  required String templateId,
  required String templateName,
}) async {
  final ref = _db
      .collection('transactions')
      .doc(txId)
      .collection('filled_forms')
      .doc();
  final now = DateTime.now();
  await ref.set(
    FilledForm(
      id: ref.id,
      transactionId: txId,
      templateId: templateId,
      templateName: templateName,
      createdAt: now,
      updatedAt: now,
    ).toFirestore(),
  );
  return ref.id;
}

Future<void> saveFilledFormDraft(
  String txId,
  String formId,
  Map<String, dynamic> fieldValues,
) async {
  await _db
      .collection('transactions')
      .doc(txId)
      .collection('filled_forms')
      .doc(formId)
      .update({
        'fieldValues': fieldValues,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

Future<void> completeFilledForm(
  String txId,
  String formId,
  String pdfStoragePath,
) async {
  await _db
      .collection('transactions')
      .doc(txId)
      .collection('filled_forms')
      .doc(formId)
      .update({
        'status': 'complete',
        'pdfStoragePath': pdfStoragePath,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

// ─── Signing requests ─────────────────────────────────────────────────────────

/// A single signing request by token — readable without auth.
final signingRequestProvider =
    StreamProvider.family<SigningRequest?, String>((ref, token) {
  return _db
      .collection('signing_requests')
      .doc(token)
      .snapshots()
      .map((s) => s.exists ? SigningRequest.fromFirestore(s) : null);
});

/// All pending signing requests for a given filledFormId (watched by agent).
final pendingSigningRequestsProvider =
    StreamProvider.family<List<SigningRequest>, String>((ref, filledFormId) {
  return _db
      .collection('signing_requests')
      .where('filledFormId', isEqualTo: filledFormId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map(SigningRequest.fromFirestore).toList());
});

Future<String> createSigningRequest(SigningRequest request) async {
  final doc = _db.collection('signing_requests').doc();
  await doc.set(request.toFirestore());
  return doc.id;
}

Future<void> completeSigningRequest(
  String token,
  String signedPdfStoragePath,
) async {
  await _db.collection('signing_requests').doc(token).update({
    'status': 'signed',
    'signedAt': FieldValue.serverTimestamp(),
    'signedPdfStoragePath': signedPdfStoragePath,
  });
}

Future<Contact?> fetchContact(String contactId) async {
  final snap = await _db.collection('contacts').doc(contactId).get();
  return snap.exists ? Contact.fromFirestore(snap) : null;
}

// ─── Template field editing ───────────────────────────────────────────────────

/// Saves the edited step/field structure back to Firestore and marks schema ready.
Future<void> saveTemplateSteps(
  String templateId,
  List<FormStep> steps,
) async {
  await _db.collection('form_templates').doc(templateId).update({
    'steps': steps.map((s) => s.toMap()).toList(),
    'schemaReady': true,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// Calls the detectFormFields Cloud Function.
/// Returns the raw field list returned by AI; Firestore is also updated by the function.
Future<List<Map<String, dynamic>>> detectFormFieldsViaAI({
  required String templateId,
  required String boardId,
}) async {
  final fn = FirebaseFunctions.instance.httpsCallable(
    'detectFormFields',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
  );
  final result = await fn.call({'templateId': templateId, 'boardId': boardId});
  return List<Map<String, dynamic>>.from(
    (result.data as Map<dynamic, dynamic>)['fields'] as List,
  );
}
