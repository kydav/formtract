import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as sgMail from '@sendgrid/mail';
import Anthropic from '@anthropic-ai/sdk';

admin.initializeApp();

// Set via: firebase functions:secrets:set SENDGRID_API_KEY
// Or legacy config: firebase functions:config:set sendgrid.api_key="SG.xxx"
function getSendGridKey(): string {
  return (
    process.env['SENDGRID_API_KEY'] ??
    (functions.config()['sendgrid'] as { api_key?: string } | undefined)?.api_key ??
    ''
  );
}

interface SendSigningEmailData {
  token: string;
  clientEmail: string;
  clientName?: string;
}

export const sendSigningEmail = functions.https.onCall(
  async (data: SendSigningEmailData, context) => {
    // Must be a real (non-anonymous) authenticated agent.
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const provider = context.auth.token['firebase']?.['sign_in_provider'] as string | undefined;
    if (provider === 'anonymous') {
      throw new functions.https.HttpsError('unauthenticated', 'Anonymous users cannot send signing emails.');
    }

    const { token, clientEmail, clientName } = data;
    if (!token || !clientEmail) {
      throw new functions.https.HttpsError('invalid-argument', 'token and clientEmail are required.');
    }

    // Load and validate the signing request.
    const doc = await admin.firestore().collection('signing_requests').doc(token).get();
    if (!doc.exists) {
      throw new functions.https.HttpsError('not-found', 'Signing request not found.');
    }
    const sr = doc.data()!;
    if (sr['agentId'] !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'This signing request does not belong to you.');
    }
    if (sr['status'] !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'This document has already been signed or expired.');
    }

    const apiKey = getSendGridKey();
    if (!apiKey) {
      throw new functions.https.HttpsError('internal', 'SendGrid API key not configured. Run: firebase functions:secrets:set SENDGRID_API_KEY');
    }
    sgMail.setApiKey(apiKey);

    const signingUrl = `https://formtract.web.app/sign/${token}`;
    const expiresAt = (sr['expiresAt'] as admin.firestore.Timestamp | undefined)?.toDate();
    const expiryStr = expiresAt
      ? expiresAt.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
      : '7 days from now';
    const templateName = sr['templateName'] as string;
    const greeting = clientName ? `Hi ${clientName},` : 'Hi,';

    await sgMail.send({
      to: clientEmail,
      from: { email: 'noreply@formtract.app', name: 'Formtract' },
      subject: `Please sign: ${templateName}`,
      html: `
        <div style="font-family:sans-serif;max-width:560px;margin:0 auto;padding:32px 20px;">
          <div style="margin-bottom:24px;">
            <span style="background:#2563EB;color:#fff;padding:6px 14px;border-radius:6px;font-weight:700;font-size:14px;letter-spacing:0.5px;">
              formtract
            </span>
          </div>
          <h2 style="color:#0D1B35;margin:0 0 12px;font-size:22px;">${greeting}</h2>
          <p style="color:#444;line-height:1.6;margin:0 0 8px;">
            Your agent has requested your electronic signature on the following document:
          </p>
          <p style="font-weight:600;color:#0D1B35;font-size:17px;margin:0 0 8px;">${templateName}</p>
          <p style="color:#888;font-size:13px;margin:0 0 32px;">This link expires on <strong>${expiryStr}</strong>.</p>
          <a href="${signingUrl}"
             style="background:#2563EB;color:#fff;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:600;font-size:16px;display:inline-block;">
            Review &amp; Sign Document →
          </a>
          <p style="color:#bbb;font-size:12px;margin:40px 0 0;border-top:1px solid #eee;padding-top:20px;line-height:1.8;">
            If you were not expecting this request, you can safely ignore this email.<br>
            Powered by <a href="https://formtract.web.app" style="color:#2563EB;text-decoration:none;">Formtract</a>
          </p>
        </div>
      `,
    });

    // Record the client email on the signing request for audit trail.
    await doc.ref.update({ clientEmail, emailSentAt: admin.firestore.FieldValue.serverTimestamp() });

    return { success: true };
  },
);

// ── AI form field detection ────────────────────────────────────────────────────

interface DetectedField {
  id: string;
  label: string;
  type: string;
  page: number;
  x: number;
  y: number;
  width: number;
  height: number;
  required: boolean;
  options: string[];
  contactMapping: string | null;
}

const FIELD_DETECTION_PROMPT = `IMPORTANT: Your response must be ONLY a raw JSON array — no markdown, no code fences, no explanation text before or after. Start your response with [ and end with ].

You are analyzing a real estate form PDF to extract all fillable entry fields.

For each field, return a JSON object with these exact properties:
- "id": camelCase identifier derived from the label (e.g. "buyerFirstName", "purchasePrice", "agentSignature")
- "label": the human-readable label exactly as printed on the form
- "type": one of: "text", "email", "phone", "date", "number", "checkbox", "radio", "signature", "initials", "dropdown"
- "page": page number (1-indexed)
- "x": left edge as % of page width (0-100, measured from left)
- "y": top edge as % of page height (0-100, measured from top)
- "width": field width as % of page width (0-100)
- "height": field height as % of page height (0-100)
- "required": true if the field appears mandatory
- "options": array of string choices for radio/dropdown fields, otherwise []
- "contactMapping": one of the following if the field clearly maps to a known property, otherwise null:
  "agent.name", "agent.email",
  "buyer.fullName", "buyer.firstName", "buyer.lastName", "buyer.email", "buyer.phone", "buyer.address",
  "property.address", "property.city", "property.state", "property.zipCode", "property.price"

Return ONLY a valid JSON array. No explanation, no markdown fences, no extra text.`;

export const detectFormFields = functions
  .runWith({ timeoutSeconds: 120, memory: '512MB', secrets: ['ANTHROPIC_API_KEY'] })
  .https.onCall(async (data: { templateId: string; boardId: string }, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { templateId, boardId } = data as { templateId: string; boardId: string };
    if (!templateId || !boardId) {
      throw new functions.https.HttpsError('invalid-argument', 'templateId and boardId are required.');
    }

    // Download the PDF from Firebase Storage.
    functions.logger.log('detectFormFields: downloading PDF', { templateId, boardId });
    const bucket = admin.storage().bucket();
    const file = bucket.file(`templates/${boardId}/${templateId}.pdf`);
    const [pdfBytes] = await file.download();
    const base64Pdf = pdfBytes.toString('base64');
    functions.logger.log('detectFormFields: PDF downloaded', { bytes: pdfBytes.length });

    // Call Claude via Anthropic API.
    const anthropicKey = process.env['ANTHROPIC_API_KEY'] ?? '';
    if (!anthropicKey) {
      throw new functions.https.HttpsError('internal', 'ANTHROPIC_API_KEY not configured. Run: firebase functions:secrets:set ANTHROPIC_API_KEY');
    }
    functions.logger.log('detectFormFields: calling Claude');
    const anthropic = new Anthropic({ apiKey: anthropicKey });

    const message = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 8192,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'document' as const,
            source: {
              type: 'base64' as const,
              media_type: 'application/pdf' as const,
              data: base64Pdf,
            },
          },
          { type: 'text' as const, text: FIELD_DETECTION_PROMPT },
        ],
      }],
    });

    const rawText = message.content[0]?.type === 'text' ? message.content[0].text : '[]';
    functions.logger.log('detectFormFields: Claude responded', {
      chars: rawText.length,
      preview: rawText.slice(0, 200),
      stopReason: message.stop_reason,
    });

    // Strip any markdown code fence (handles ``` or ` , json/JSON, extra whitespace).
    let jsonText = rawText
      .replace(/^`{1,3}(?:json)?\s*\n?/i, '')
      .replace(/\n?`{1,3}\s*$/i, '')
      .trim();

    // Find the outermost JSON array bounds (handles preamble text and truncation).
    const jsonStart = jsonText.indexOf('[');
    const jsonEnd = jsonText.lastIndexOf(']');
    if (jsonStart !== -1 && jsonEnd > jsonStart) {
      jsonText = jsonText.slice(jsonStart, jsonEnd + 1);
    }

    let fields: DetectedField[];
    try {
      fields = JSON.parse(jsonText) as DetectedField[];
    } catch {
      throw new functions.https.HttpsError('internal', `AI returned invalid JSON: ${rawText.slice(0, 200)}`);
    }
    functions.logger.log('detectFormFields: parsed fields', { count: fields.length });

    // Group fields into steps by page, then save the full template schema.
    const byPage = new Map<number, DetectedField[]>();
    for (const f of fields) {
      const page = f.page ?? 1;
      if (!byPage.has(page)) byPage.set(page, []);
      byPage.get(page)!.push(f);
    }

    const steps = Array.from(byPage.entries())
      .sort(([a], [b]) => a - b)
      .map(([page, pageFields]) => ({
        title: `Page ${page}`,
        fields: pageFields.map((f) => ({
          id: f.id,
          label: f.label,
          type: f.type,
          required: f.required ?? false,
          options: f.options ?? [],
          page: f.page,
          x: f.x,
          y: f.y,
          width: f.width,
          height: f.height,
          contactMapping: f.contactMapping ?? null,
        })),
      }));

    functions.logger.log('detectFormFields: writing to Firestore', { templateId });
    await admin.firestore().collection('form_templates').doc(templateId).update({
      steps,
      schemaReady: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    functions.logger.log('detectFormFields: done');

    return { fields };
  });

// ── AI field labeling ──────────────────────────────────────────────────────────

export const labelFormFields = functions
  .runWith({ timeoutSeconds: 120, memory: '512MB', secrets: ['ANTHROPIC_API_KEY'] })
  .https.onCall(async (
    data: { templateId: string; boardId: string; fieldNames: string[] },
    context,
  ) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { templateId, boardId, fieldNames } = data;
    if (!templateId || !boardId || !Array.isArray(fieldNames) || fieldNames.length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'templateId, boardId, and fieldNames are required.');
    }

    functions.logger.log('labelFormFields: downloading PDF', { templateId, fieldCount: fieldNames.length });
    const bucket = admin.storage().bucket();
    const file = bucket.file(`templates/${boardId}/${templateId}.pdf`);
    const [pdfBytes] = await file.download();
    const base64Pdf = pdfBytes.toString('base64');

    const anthropicKey = process.env['ANTHROPIC_API_KEY'] ?? '';
    if (!anthropicKey) {
      throw new functions.https.HttpsError('internal', 'ANTHROPIC_API_KEY not configured.');
    }

    const fieldList = fieldNames.map((n, i) => `${i + 1}. "${n}"`).join('\n');
    const prompt = `You are reading a fillable real estate PDF form. The form has AcroForm fields with these internal names:\n\n${fieldList}\n\nFor each field name, look at the text printed on the form near or before that field and return a concise, human-readable label describing what the user should fill in (e.g. "Buyer Name", "Purchase Price", "Closing Date", "Inspection Deadline").\n\nRules:\n- If the field is in a dates/deadlines table, include the deadline name (e.g. "Record Title Deadline", "Closing Date")\n- For checkbox fields, describe what checking the box means (e.g. "Joint Tenants", "Conventional Loan")\n- Keep labels short — 1-5 words\n- If you cannot determine the label, return the field name as-is\n\nRespond with ONLY a raw JSON object mapping each field name to its label. No markdown, no explanation. Example: {"fieldName": "Human Label"}`;

    const anthropic = new Anthropic({ apiKey: anthropicKey });
    const message = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 4096,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'document' as const,
            source: { type: 'base64' as const, media_type: 'application/pdf' as const, data: base64Pdf },
          },
          { type: 'text' as const, text: prompt },
        ],
      }],
    });

    const rawText = message.content[0]?.type === 'text' ? message.content[0].text : '{}';
    functions.logger.log('labelFormFields: Claude responded', { chars: rawText.length, stopReason: message.stop_reason });

    let jsonText = rawText
      .replace(/^`{1,3}(?:json)?\s*\n?/i, '')
      .replace(/\n?`{1,3}\s*$/i, '')
      .trim();
    const jsonStart = jsonText.indexOf('{');
    const jsonEnd = jsonText.lastIndexOf('}');
    if (jsonStart !== -1 && jsonEnd > jsonStart) {
      jsonText = jsonText.slice(jsonStart, jsonEnd + 1);
    }

    let labels: Record<string, string>;
    try {
      labels = JSON.parse(jsonText) as Record<string, string>;
    } catch {
      throw new functions.https.HttpsError('internal', `AI returned invalid JSON: ${rawText.slice(0, 200)}`);
    }

    functions.logger.log('labelFormFields: saving labels', { count: Object.keys(labels).length });
    await admin.firestore().collection('form_templates').doc(templateId).update({
      fieldLabels: labels,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { labels };
  });
