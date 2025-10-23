// server.mjs — Node 18+
// Run: node server.mjs
import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import crypto from 'crypto'; // (kept if you later need it)
import morgan from 'morgan';
import helmet from 'helmet';
import fetch from 'node-fetch';

import { initializeApp, applicationDefault, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

// ---------- ENV ----------
const PORT = Number(process.env.PORT || 8080);
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;

const QPAY_ID_BASE   = process.env.QPAY_ID_BASE;   // OSGEapiacc
const QPAY_PWD       = process.env.QPAY_PWD;       // OSGE!123
const QPAY_MODE      = (process.env.QPAY_MODE || 'Test'); // Test | Live
const QPAY_GATEWAY   = process.env.QPAY_GATEWAY_URL || 'https://pg.qpayindia.com/WWWS/Merchant/Home/MerchantPage.aspx';

// ---------- FIREBASE ----------
function initFirebase() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      let raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON.trim();
      if (!raw.startsWith('{')) raw = Buffer.from(raw, 'base64').toString('utf8');
      const sa = JSON.parse(raw);
      initializeApp({ credential: cert(sa) });
      console.log('✅ Firebase initialized (Service Account JSON)');
    } else {
      initializeApp({ credential: applicationDefault() });
      console.log('✅ Firebase initialized (Application Default)');
    }
  } catch (e) {
    console.error('❌ Firebase init failed:', e);
    process.exit(1);
  }
}
initFirebase();
const db = getFirestore();

// ---------- APP ----------
const app = express();

// Helmet: keep it for everything else, but we'll relax CSP on the auto-post page
app.use(helmet({
  // we'll set CSP per-route for the auto-post page
  contentSecurityPolicy: {
    useDefaults: true,
    directives: {
      // safe defaults elsewhere
      "script-src": ["'self'"],
      "style-src": ["'self'", "'unsafe-inline'"],
      "img-src": ["'self'", "data:"],
      "object-src": ["'none'"],
      "base-uri": ["'self'"],
      "frame-ancestors": ["'self'"],
      "upgrade-insecure-requests": [],
    }
  },
  crossOriginResourcePolicy: false,
}));
app.use(morgan('tiny'));
app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// ---------- HELPERS ----------
async function updateUserBalance(uid, amount, description, type, extra = {}) {
  const userRef = db.collection('users').doc(uid);
  const ledgerRef = userRef.collection('wallet_ledger').doc();
  return db.runTransaction(async (t) => {
    const snap = await t.get(userRef);
    if (!snap.exists) throw new Error('User document does not exist');
    const currentBalance = Number(snap.data().walletBalance || 0);
    const newBalance = currentBalance + Number(amount);
    if (newBalance < 0) throw new Error('Insufficient funds');
    t.update(userRef, { walletBalance: newBalance });
    t.set(ledgerRef, {
      amount: Number(amount),
      type, // 'CREDIT' | 'DEBIT'
      description,
      balanceBefore: currentBalance,
      balanceAfter: newBalance,
      createdAt: new Date(),
      ...extra,
    });
    return newBalance;
  });
}

// ---------- ROUTES ----------
app.get('/healthz', (req, res) => res.status(200).json({ ok: true }));

// Create the order, then respond with a URL that shows a self-submitting form to QPay
app.post('/qpay-india/create-order', async (req, res) => {
  try {
    const { uid, amount } = req.body ?? {};
    const amt = Number(amount);
    if (!uid || !amt || isNaN(amt) || amt <= 0) {
      return res.status(400).json({ error: 'Invalid uid or amount' });
    }
    if (!QPAY_ID_BASE || !QPAY_PWD) {
      return res.status(500).json({ error: 'QPay credentials not configured' });
    }

    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    const orderId = `PP${Date.now()}`;
    const amountStr = amt.toFixed(2);

    // QPayID = <merchantId>`<base64(amount)>
    const encodedAmount = Buffer.from(amountStr).toString('base64');
    const QPayID = `${QPAY_ID_BASE}\`${encodedAmount}`;

    // Persist a PENDING order for your own tracking
    await db.collection('orders').doc(orderId).set({
      uid,
      amount: amt,
      status: 'PENDING',
      createdAt: new Date(),
      gateway: 'qpay',
      mode: QPAY_MODE,
    });

    // We’ll launch the local “start” page, which auto-posts to QPay
    const launchUrl = `${PUBLIC_BASE_URL}/qpay-india/start/${orderId}`;
    // Store the values we need for the form in Firestore
    await db.collection('orders').doc(orderId).update({
      _qpay_form_payload: {
        QPayID,
        QPayPWD: QPAY_PWD,
        OrderID: orderId,
        Mode: QPAY_MODE,                  // Test | Live
        PaymentOption: 'C,N,U',           // Cards, Netbanking, UPI
        CurrencyCode: 'INR',
        // Use your deep link / callback URL so your app can react
        // NOTE: QPay’s PDF calls this ResponseActivity for Android SDK, but web works fine with a URL param.
        ResponseActivity: `${PUBLIC_BASE_URL}/qpay-india/callback`,
        Email: userDoc.data().email || 'notprovided@example.com',
        Phone: userDoc.data().phone || '9999999999',
        // Optional but often supported:
        TransactionType: 'PURCHASE',
        ReturnURL: `${PUBLIC_BASE_URL}/qpay-india/callback`,
      }
    });

    return res.status(200).json({ orderId, launchUrl });
  } catch (e) {
    console.error('QPay create-order error:', e);
    return res.status(500).json({ error: 'Failed to create payment order' });
  }
});

// The auto-post page (must allow inline script on THIS response)
app.get('/qpay-india/start/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    const orderDoc = await db.collection('orders').doc(orderId).get();
    if (!orderDoc.exists) return res.status(404).send('Order not found');

    const payload = orderDoc.data()._qpay_form_payload;
    if (!payload) return res.status(400).send('Order form payload missing');

    // Relax CSP JUST for this HTML so the inline script can run
    res.setHeader('Content-Security-Policy',
      "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; frame-ancestors 'self'; object-src 'none'");

    // Minimal HTML that posts the exact fields QPay expects (NO custom Hash)
    res.status(200).send(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Redirecting to QPay…</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#222} .card{max-width:560px;padding:24px;border:1px solid #e8e8e8;border-radius:12px;box-shadow:0 10px 30px rgba(0,0,0,.05)} .muted{color:#666;font-size:14px}</style>
</head>
<body>
  <div class="card">
    <h3>Taking you to QPay…</h3>
    <p class="muted">Please wait while we open the payment gateway.</p>
    <form id="f" action="${QPAY_GATEWAY}" method="post">
      <input type="hidden" name="QPayID"         value="${payload.QPayID}">
      <input type="hidden" name="QPayPWD"        value="${payload.QPayPWD}">
      <input type="hidden" name="OrderID"        value="${payload.OrderID}">
      <input type="hidden" name="PaymentOption"  value="${payload.PaymentOption}">
      <input type="hidden" name="Mode"           value="${payload.Mode}">
      <input type="hidden" name="Phone"          value="${payload.Phone}">
      <input type="hidden" name="Email"          value="${payload.Email}">
      <input type="hidden" name="CurrencyCode"   value="${payload.CurrencyCode}">
      <input type="hidden" name="ResponseActivity" value="${payload.ResponseActivity}">
      <input type="hidden" name="TransactionType"  value="${payload.TransactionType}">
      <input type="hidden" name="ReturnURL"        value="${payload.ReturnURL}">
      <noscript><p>JavaScript is required. Click the button to continue.</p><button type="submit">Continue</button></noscript>
    </form>
    <script>setTimeout(function(){document.getElementById('f').submit();}, 50);</script>
  </div>
</body>
</html>`);
  } catch (e) {
    console.error('start page error:', e);
    res.status(500).send('Error');
  }
});

// QPay calls this after payment (we accept both GET/POST)
app.all('/qpay-india/callback', async (req, res) => {
  try {
    const body = Object.keys(req.body ?? {}).length ? req.body : req.query;
    const MerchantOrderID = body.MerchantOrderID || body.OrderID || body.orderId || '';
    const ResponseCode   = String(body.ResponseCode ?? '');
    const Message        = body.Message || '';

    if (!MerchantOrderID) {
      return res.status(400).json({ ok:false, error:'MissingOrderID', raw: body });
    }

    const orderRef = db.collection('orders').doc(MerchantOrderID);
    const orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      return res.status(404).json({ ok:false, error:'OrderNotFound', raw: body });
    }

    const order = orderDoc.data();
    if (order.status === 'COMPLETED') {
      return res.json({ ok:true, status:'COMPLETED', orderId: MerchantOrderID });
    }

    if (ResponseCode === '200' || ResponseCode === '100') {
      // 200=Approved (live), 100=Approved in test mode (from their doc)
      await updateUserBalance(
        order.uid,
        Number(order.amount),
        'Wallet Top-up via QPay',
        'CREDIT',
        { orderId: MerchantOrderID, qpayResponse: body }
      );
      await orderRef.update({ status: 'COMPLETED', qpayResponse: body });
      return res.json({ ok:true, status:'COMPLETED', orderId: MerchantOrderID });
    } else {
      await orderRef.update({ status: 'FAILED', qpayResponse: body });
      return res.status(400).json({
        ok:false,
        status:'FAILED',
        code: ResponseCode || null,
        message: Message || 'Payment failed',
        orderId: MerchantOrderID,
        raw: body
      });
    }
  } catch (e) {
    console.error('QPay callback error:', e);
    return res.status(500).json({ ok:false, error:'InternalServerError' });
  }
});

// ---------- START ----------
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server running on http://0.0.0.0:${PORT}`);
  console.log(`   Public base URL: ${PUBLIC_BASE_URL}`);
  console.log(`   QPay Mode: ${QPAY_MODE}`);
  console.log(`   Flow: form (no hash)`);
  console.log(`   QPay Gateway (form): ${QPAY_GATEWAY}`);
});
