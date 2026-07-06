import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as sgMail from '@sendgrid/mail';

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
