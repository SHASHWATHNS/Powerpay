// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Helper: verify Authorization: Bearer <idToken>
// Returns decoded token (with uid and custom claims) or throws (with .code property)
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
    // require admin claim
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

// ---------------------- HTTP: createUserByAdminHttp ----------------------
// Create user endpoint (expects JSON body with email, password, name, ...)
// Requires Authorization: Bearer <idToken> of a user with custom claim `admin: true`
exports.createUserByAdminHttp = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send({ error: 'Only POST allowed' });
  try {
    const decoded = await verifyAdmin(req); // will throw if not admin
    const callerUid = decoded.uid;

    const body = req.body || {};
    const { email, password, name, phoneNumber = '', address = '', panNumber = '', aadharNumber = '', commissionSlab } = body;

    if (!email || !password || !name) {
      return res.status(400).json({ error: 'Missing required fields: email, password, name' });
    }

    // create user in Firebase Auth
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
      createdBy: callerUid, // set createdBy to the admin/distributor who called endpoint
      backendCreatedBy: 'createUserByAdminHttp',
    };

    if (commissionSlab !== undefined) {
      const slabNum = Number(commissionSlab);
      if (!isNaN(slabNum)) userDoc.commissionSlab = slabNum;
    }

    await admin.firestore().collection('users').doc(uid).set(userDoc);

    return res.json({ success: true, uid });
  } catch (err) {
    console.error('createUserByAdminHttp error:', err);
    const code = err && err.code ? err.code : 500;
    const msg = err && err.message ? err.message : 'Internal error';
    return res.status(code === 401 ? 401 : code === 403 ? 403 : 500).json({ error: msg });
  }
});

// ---------------------- HTTP: deleteUserByAdminHttp ----------------------
exports.deleteUserByAdminHttp = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send({ error: 'Only POST allowed' });
  try {
    await verifyAdmin(req);

    const body = req.body || {};
    const { uid } = body;
    if (!uid) return res.status(400).json({ error: 'Missing required field: uid' });

    // revoke sessions, delete auth user, delete Firestore doc
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

// ---------------------- Callable: updateUser ----------------------
// Callable function to allow distributors (owner) or admins to update allowed fields.
//
// data: {
//   uid: string,  // target user uid to update
//   name?: string,
//   phoneNumber?: string,
//   address?: string,
//   panNumber?: string,
//   aadharNumber?: string,
//   commissionSlab?: number|string
// }
// Caller must be authenticated. Update is allowed when:
//  - caller is admin (custom claim `admin: true`) OR
//  - caller is the same as users.{uid}.createdBy (i.e. distributor who created the retailer).
exports.updateUser = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }

    const callerUid = context.auth.uid;
    const callerClaims = context.auth.token || {};
    const isAdmin = !!callerClaims.admin;

    const targetUid = (data && data.uid) ? String(data.uid) : '';
    if (!targetUid) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing uid to update');
    }

    // Build updates map with allowed fields only
    const updates = {};
    if (typeof data.name === 'string') updates.name = data.name.trim();
    if (typeof data.phoneNumber === 'string') updates.phoneNumber = data.phoneNumber.trim();
    if (typeof data.address === 'string') updates.address = data.address.trim();
    if (typeof data.panNumber === 'string') updates.panNumber = data.panNumber.trim().toUpperCase();
    if (typeof data.aadharNumber === 'string') updates.aadharNumber = data.aadharNumber.trim();
    if (data.commissionSlab !== undefined) {
      const slab = Number(data.commissionSlab);
      if (!isNaN(slab)) updates.commissionSlab = slab;
    }

    if (Object.keys(updates).length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'No valid fields to update');
    }

    const userRef = admin.firestore().collection('users').doc(targetUid);
    const doc = await userRef.get();
    if (!doc.exists) {
      throw new functions.https.HttpsError('not-found', 'Target user not found');
    }

    const docData = doc.data() || {};
    const createdBy = docData.createdBy || null;

    // Allow only admins or the distributor that created this user
    if (!isAdmin && createdBy !== callerUid) {
      throw new functions.https.HttpsError('permission-denied', 'You are not allowed to update this user');
    }

    updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await userRef.update(updates);

    return { success: true, updated: updates };
  } catch (err) {
    if (err instanceof functions.https.HttpsError) throw err;
    console.error('updateUser error:', err);
    throw new functions.https.HttpsError('internal', err && err.message ? err.message : String(err));
  }
});

// ---------------------- Callable: transferWallet ----------------------
// (Kept your original logic with small formatting/consistency adjustments)
exports.transferWallet = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const distributorUid = context.auth.uid;

    const toUserId = data && data.toUserId ? String(data.toUserId) : '';
    const amount = Number(data && data.amount ? data.amount : 0);
    const toUserName = data && data.toUserName ? String(data.toUserName) : null;

    if (!toUserId || isNaN(amount) || amount <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid toUserId or amount.');
    }
    if (amount < 10) {
      throw new functions.https.HttpsError('failed-precondition', 'Minimum transfer is ₹10.');
    }

    const db = admin.firestore();

    // Verify distributor exists in index
    const idxSnap = await db.collection('distributors_by_uid').doc(distributorUid).get();
    if (!idxSnap.exists) {
      throw new functions.https.HttpsError('permission-denied', 'Caller is not a distributor.');
    }

    // helper to detect where balance is stored
    async function detectBalanceDocRef(uid) {
      const candidates = [
        db.collection('users').doc(uid),
        db.collection('wallets').doc(uid),
        db.collection('distributors').doc(uid)
      ];
      for (const ref of candidates) {
        const snap = await ref.get();
        if (snap.exists) return ref;
      }
      return db.collection('users').doc(uid); // default
    }

    const distributorRef = await detectBalanceDocRef(distributorUid);
    const userRef = await detectBalanceDocRef(toUserId);
    const txLogRef = db.collection('wallet_transactions').doc();
    const distributorPaymentRef = db.collection('distributor_payments').doc();

    const parseBalanceFromData = (d) => {
      if (!d) return 0;
      const raw = (d.walletBalance !== undefined) ? d.walletBalance
                : (d.balance !== undefined) ? d.balance
                : 0;
      if (typeof raw === 'number') return raw;
      const cleaned = String(raw).replace(/[^\d\.-]/g, '');
      const n = Number(cleaned);
      return isNaN(n) ? 0 : n;
    };

    await db.runTransaction(async (tx) => {
      const distSnap = await tx.get(distributorRef);
      const userSnap = await tx.get(userRef);

      const distData = distSnap.exists ? distSnap.data() : null;
      const userData = userSnap.exists ? userSnap.data() : null;

      const distBal = parseBalanceFromData(distData);
      const userBal = parseBalanceFromData(userData);

      if (distBal < amount) {
        throw new functions.https.HttpsError('failed-precondition',
          `insufficient-funds: distributor has ₹${distBal} (requested ₹${amount})`);
      }

      if (!distSnap.exists) {
        tx.set(distributorRef, {
          walletBalance: 0,
          ownerId: distributorUid,
          role: 'distributor',
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
      if (!userSnap.exists) {
        tx.set(userRef, {
          walletBalance: 0,
          ownerId: toUserId,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }

      tx.update(distributorRef, {
        walletBalance: distBal - amount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      tx.update(userRef, {
        walletBalance: userBal + amount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      tx.set(txLogRef, {
        type: 'transfer',
        fromUserId: distributorUid,
        fromUserEmail: context.auth.token.email || null,
        toUserId,
        toUserName,
        amount,
        description: 'Distributor recharge for user',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: 'completed'
      });

      tx.set(distributorPaymentRef, {
        userId: toUserId,
        userName: toUserName,
        amount,
        distributorId: distributorUid,
        distributorEmail: context.auth.token.email || null,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: 'completed',
        type: 'wallet_transfer'
      });
    });

    return { success: true, message: `Transferred ₹${amount} to ${toUserId}` };
  } catch (err) {
    if (err instanceof functions.https.HttpsError) throw err;
    console.error('transferWallet error:', err);
    throw new functions.https.HttpsError('internal', err.message || String(err));
  }
});
