// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Helper: verify Authorization: Bearer <idToken>
async function verifyAdmin(req) {
  const authHeader = (req.get('Authorization') || req.get('authorization') || '');
  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') {
    const err = new Error('Missing or malformed Authorization header');
    err.code = 401;
    throw err;
  }
  const idToken = parts[1];
  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    if (!decoded.admin) {
      const err = new Error('Not an admin');
      err.code = 403;
      throw err;
    }
    return decoded;
  } catch (err) {
    const e = new Error('Invalid ID token');
    e.code = 401;
    e.details = err;
    throw e;
  }
}

// Create user endpoint (expects JSON body with email, password, name, ...)
exports.createUserByAdminHttp = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send({ error: 'Only POST' });
  try {
    await verifyAdmin(req);

    const body = req.body || {};
    const { email, password, name, phoneNumber = '', address = '', panNumber = '', aadharNumber = '' } = body;

    if (!email || !password || !name) {
      return res.status(400).json({ error: 'Missing required fields: email, password, name' });
    }

    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: name,
      phoneNumber: phoneNumber || undefined,
    });

    const uid = userRecord.uid;
    const userDoc = {
      name,
      email,
      phoneNumber,
      address,
      panNumber,
      aadharNumber,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      walletBalance: 0,
    };

    await admin.firestore().collection('users').doc(uid).set(userDoc);

    return res.json({ success: true, uid });
  } catch (err) {
    console.error('createUserByAdminHttp error:', err);
    const code = err && err.code ? err.code : 500;
    const msg = err && err.message ? err.message : 'Internal error';
    return res.status(code === 401 ? 401 : code === 403 ? 403 : 500).json({ error: msg });
  }
});

// Delete user endpoint (expects JSON body with uid)
exports.deleteUserByAdminHttp = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send({ error: 'Only POST' });
  try {
    await verifyAdmin(req);

    const body = req.body || {};
    const { uid } = body;
    if (!uid) return res.status(400).json({ error: 'Missing required field: uid' });

    await admin.auth().revokeRefreshTokens(uid);
    await admin.auth().deleteUser(uid);
    await admin.firestore().collection('users').doc(uid).delete();

    return res.json({ success: true, uid });
  } catch (err) {
    console.error('deleteUserByAdminHttp error:', err);
    const code = err && err.code ? err.code : 500;
    const msg = err && err.message ? err.message : 'Internal error';
    if (msg && msg.includes('user-not-found')) {
      return res.status(404).json({ error: 'User not found' });
    }
    return res.status(code === 401 ? 401 : code === 403 ? 403 : 500).json({ error: msg });
  }
});
