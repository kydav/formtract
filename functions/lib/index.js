"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.detectFormFields = exports.sendSigningEmail = void 0;
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const sgMail = require("@sendgrid/mail");
const vertexai_1 = require("@google-cloud/vertexai");
admin.initializeApp();
// Set via: firebase functions:secrets:set SENDGRID_API_KEY
// Or legacy config: firebase functions:config:set sendgrid.api_key="SG.xxx"
function getSendGridKey() {
    var _a, _b, _c;
    return ((_c = (_a = process.env['SENDGRID_API_KEY']) !== null && _a !== void 0 ? _a : (_b = functions.config()['sendgrid']) === null || _b === void 0 ? void 0 : _b.api_key) !== null && _c !== void 0 ? _c : '');
}
exports.sendSigningEmail = functions.https.onCall(async (data, context) => {
    var _a, _b;
    // Must be a real (non-anonymous) authenticated agent.
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const provider = (_a = context.auth.token['firebase']) === null || _a === void 0 ? void 0 : _a['sign_in_provider'];
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
    const sr = doc.data();
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
    const expiresAt = (_b = sr['expiresAt']) === null || _b === void 0 ? void 0 : _b.toDate();
    const expiryStr = expiresAt
        ? expiresAt.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
        : '7 days from now';
    const templateName = sr['templateName'];
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
});
const FIELD_DETECTION_PROMPT = `You are analyzing a real estate form PDF to extract all fillable entry fields.

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
exports.detectFormFields = functions
    .runWith({ timeoutSeconds: 120, memory: '512MB' })
    .https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { templateId, boardId } = data;
    if (!templateId || !boardId) {
        throw new functions.https.HttpsError('invalid-argument', 'templateId and boardId are required.');
    }
    // Download the PDF from Firebase Storage.
    const bucket = admin.storage().bucket();
    const file = bucket.file(`templates/${boardId}/${templateId}.pdf`);
    const [pdfBytes] = await file.download();
    const base64Pdf = pdfBytes.toString('base64');
    // Call Vertex AI Gemini 2.0 Flash.
    const projectId = (_b = (_a = process.env['GCLOUD_PROJECT']) !== null && _a !== void 0 ? _a : process.env['GOOGLE_CLOUD_PROJECT']) !== null && _b !== void 0 ? _b : 'formtract';
    const vertex = new vertexai_1.VertexAI({ project: projectId, location: 'us-central1' });
    const model = vertex.getGenerativeModel({ model: 'gemini-2.0-flash-001' });
    const result = await model.generateContent({
        contents: [{
                role: 'user',
                parts: [
                    { inlineData: { mimeType: 'application/pdf', data: base64Pdf } },
                    { text: FIELD_DETECTION_PROMPT },
                ],
            }],
        generationConfig: { responseMimeType: 'application/json' },
    });
    const rawText = (_h = (_g = (_f = (_e = (_d = (_c = result.response.candidates) === null || _c === void 0 ? void 0 : _c[0]) === null || _d === void 0 ? void 0 : _d.content) === null || _e === void 0 ? void 0 : _e.parts) === null || _f === void 0 ? void 0 : _f[0]) === null || _g === void 0 ? void 0 : _g.text) !== null && _h !== void 0 ? _h : '[]';
    let fields;
    try {
        fields = JSON.parse(rawText);
    }
    catch (_k) {
        throw new functions.https.HttpsError('internal', `AI returned invalid JSON: ${rawText.slice(0, 200)}`);
    }
    // Group fields into steps by page, then save the full template schema.
    const byPage = new Map();
    for (const f of fields) {
        const page = (_j = f.page) !== null && _j !== void 0 ? _j : 1;
        if (!byPage.has(page))
            byPage.set(page, []);
        byPage.get(page).push(f);
    }
    const steps = Array.from(byPage.entries())
        .sort(([a], [b]) => a - b)
        .map(([page, pageFields]) => ({
        title: `Page ${page}`,
        fields: pageFields.map((f) => {
            var _a, _b, _c;
            return ({
                id: f.id,
                label: f.label,
                type: f.type,
                required: (_a = f.required) !== null && _a !== void 0 ? _a : false,
                options: (_b = f.options) !== null && _b !== void 0 ? _b : [],
                page: f.page,
                x: f.x,
                y: f.y,
                width: f.width,
                height: f.height,
                contactMapping: (_c = f.contactMapping) !== null && _c !== void 0 ? _c : null,
            });
        }),
    }));
    await admin.firestore().collection('form_templates').doc(templateId).update({
        steps,
        schemaReady: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { fields };
});
//# sourceMappingURL=index.js.map