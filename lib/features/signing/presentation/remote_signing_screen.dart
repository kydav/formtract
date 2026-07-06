import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/models/signing_request.dart';
import 'package:formtract/core/providers/firestore_providers.dart';
import 'package:formtract/core/services/pdf_stamper.dart';
import 'package:formtract/core/services/storage_service.dart';
import 'package:formtract/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class RemoteSigningScreen extends ConsumerWidget {
  final String token;
  const RemoteSigningScreen({required this.token, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(signingRequestProvider(token));

    return requestAsync.when(
      loading: () => const _Shell(child: Center(child: CircularProgressIndicator())),
      error: (e, _) => _Shell(child: Center(child: Text('Error: $e'))),
      data: (request) {
        if (request == null) {
          return const _Shell(
            child: _MessageView(
              icon: Icons.link_off,
              title: 'Link Not Found',
              body: 'This signing link is invalid or has been removed.',
            ),
          );
        }
        if (request.isExpired && !request.isSigned) {
          return const _Shell(
            child: _MessageView(
              icon: Icons.timer_off_outlined,
              title: 'Link Expired',
              body: 'This signing link has expired. Ask your agent to send a new one.',
            ),
          );
        }
        if (request.isSigned) {
          return _Shell(
            child: _SignedView(request: request),
          );
        }
        return _Shell(
          child: _SigningView(request: request),
        );
      },
    );
  }
}

// ── Shell ──────────────────────────────────────────────────────────────────────

class _Shell extends StatelessWidget {
  final Widget child;
  const _Shell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavyDark,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: kBlueAccent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Text(
                  'F',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'formtract',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: child,
    );
  }
}

// ── Message view (expired / not found) ────────────────────────────────────────

class _MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _MessageView({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: kTextSecondary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: kTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Already-signed view ───────────────────────────────────────────────────────

class _SignedView extends StatelessWidget {
  final SigningRequest request;
  const _SignedView({required this.request});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kSuccessGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: kSuccessGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Document Signed',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              request.templateName,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: kTextSecondary),
            ),
            if (request.signedPdfStoragePath != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  final url = await StorageService.signedFormDownloadUrl(
                    request.token,
                  );
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download Signed PDF'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Main signing view ─────────────────────────────────────────────────────────

class _SigningView extends StatefulWidget {
  final SigningRequest request;
  const _SigningView({required this.request});

  @override
  State<_SigningView> createState() => _SigningViewState();
}

class _SigningViewState extends State<_SigningView> {
  final Map<String, List<List<Offset>>> _strokes = {};
  bool _submitting = false;
  String? _error;

  bool get _hasSignature =>
      widget.request.signatureFieldIds.every(
        (id) => (_strokes[id]?.isNotEmpty ?? false),
      );

  Future<Uint8List?> _captureSignature(String fieldId) async {
    final strokes = _strokes[fieldId];
    if (strokes == null || strokes.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(300, 120);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Anonymous auth so we can read/write Firebase Storage.
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      // Download the template PDF.
      final templateBytes = await StorageService.downloadTemplate(
        boardId: widget.request.boardId,
        templateId: widget.request.templateId,
      );
      if (templateBytes == null) throw Exception('Could not load template PDF.');

      // Build the values map: start with agent pre-fills, add client signatures.
      final values = Map<String, dynamic>.from(widget.request.fieldValues);
      for (final fieldId in widget.request.signatureFieldIds) {
        final sigBytes = await _captureSignature(fieldId);
        if (sigBytes != null) values[fieldId] = sigBytes;
      }

      // Stamp and upload.
      final stamped = PdfStamper.stamp(templateBytes, values);
      final storagePath = await StorageService.uploadSignedForm(
        stamped,
        widget.request.token,
      );

      // Mark signing request complete.
      await completeSigningRequest(widget.request.token, storagePath);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: kBlueAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: kBlueAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                req.templateName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Please review and sign below',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: kTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Signature pad(s)
            ...req.signatureFieldIds.map((fieldId) {
              final strokes = _strokes[fieldId] ??= [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req.signatureFieldIds.length > 1
                        ? 'Signature ($fieldId)'
                        : 'Your Signature',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: kBorderColor, width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onPanStart: (d) {
                          setState(() =>
                              strokes.add([d.localPosition]));
                        },
                        onPanUpdate: (d) {
                          setState(() =>
                              strokes.last.add(d.localPosition));
                        },
                        child: CustomPaint(
                          painter: _StrokePainter(strokes),
                          child: strokes.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Sign here',
                                    style: TextStyle(color: kTextSecondary),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => strokes.clear()),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }),

            // Disclosure
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBorderColor),
              ),
              child: const Text(
                'By tapping "Submit Signature" below, I agree that my electronic '
                'signature constitutes my legal signature on this document, with '
                'the same effect as a handwritten signature.',
                style: TextStyle(fontSize: 12, color: kTextSecondary),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_hasSignature && !_submitting) ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Signature'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Stroke painter ────────────────────────────────────────────────────────────

class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}
