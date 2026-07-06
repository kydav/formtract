import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Handles all Firebase Storage operations for PDFs.
///
/// Path conventions:
///   templates/{boardId}/{templateId}.pdf   — original blank forms (board-level)
///   completed/{agentId}/{txId}/{formId}.pdf — stamped completed forms (per-agent)
class StorageService {
  static final _storage = FirebaseStorage.instance;

  // ── Templates ──────────────────────────────────────────────────────────────

  /// Uploads a PDF template and returns the Storage path.
  static Future<String> uploadTemplate({
    required Uint8List pdfBytes,
    required String boardId,
    required String templateId,
  }) async {
    final path = 'templates/$boardId/$templateId.pdf';
    await _storage.ref(path).putData(
      pdfBytes,
      SettableMetadata(contentType: 'application/pdf'),
    );
    return path;
  }

  /// Returns a download URL for a template PDF.
  static Future<String> templateDownloadUrl({
    required String boardId,
    required String templateId,
  }) {
    return _storage.ref('templates/$boardId/$templateId.pdf').getDownloadURL();
  }

  /// Downloads a template PDF as bytes.
  static Future<Uint8List?> downloadTemplate({
    required String boardId,
    required String templateId,
  }) {
    return _storage
        .ref('templates/$boardId/$templateId.pdf')
        .getData(50 * 1024 * 1024); // 50 MB limit
  }

  // ── Completed forms ────────────────────────────────────────────────────────

  /// Uploads a stamped/completed PDF and returns the Storage path.
  static Future<String> uploadCompletedForm({
    required Uint8List pdfBytes,
    required String agentId,
    required String transactionId,
    required String filledFormId,
  }) async {
    final path = 'completed/$agentId/$transactionId/$filledFormId.pdf';
    await _storage.ref(path).putData(
      pdfBytes,
      SettableMetadata(contentType: 'application/pdf'),
    );
    return path;
  }

  /// Returns a short-lived download URL for a completed PDF.
  static Future<String> completedFormDownloadUrl({
    required String agentId,
    required String transactionId,
    required String filledFormId,
  }) {
    return _storage
        .ref('completed/$agentId/$transactionId/$filledFormId.pdf')
        .getDownloadURL();
  }

  /// Downloads a completed PDF as bytes (for re-display or re-send).
  static Future<Uint8List?> downloadCompletedForm({
    required String agentId,
    required String transactionId,
    required String filledFormId,
  }) {
    return _storage
        .ref('completed/$agentId/$transactionId/$filledFormId.pdf')
        .getData(50 * 1024 * 1024);
  }

  /// Deletes a completed form PDF (e.g. when a transaction is deleted).
  static Future<void> deleteCompletedForm({
    required String agentId,
    required String transactionId,
    required String filledFormId,
  }) {
    return _storage
        .ref('completed/$agentId/$transactionId/$filledFormId.pdf')
        .delete();
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Gets a download URL from an arbitrary storage path stored in Firestore.
  static Future<String> urlFromPath(String storagePath) =>
      _storage.ref(storagePath).getDownloadURL();

  // ── Remote signing ─────────────────────────────────────────────────────────

  /// Uploads a client-signed PDF and returns the Storage path.
  static Future<String> uploadSignedForm(
    Uint8List pdfBytes,
    String token,
  ) async {
    final path = 'signing/$token/signed.pdf';
    await _storage.ref(path).putData(
      pdfBytes,
      SettableMetadata(contentType: 'application/pdf'),
    );
    return path;
  }

  /// Returns a download URL for a signed form.
  static Future<String> signedFormDownloadUrl(String token) =>
      _storage.ref('signing/$token/signed.pdf').getDownloadURL();
}
