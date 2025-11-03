// functions/setAdminClaim.js
const admin = require('firebase-admin');
const path = require('path');

const keyPath = path.join(__dirname, 'serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(require(keyPath)),
  // optional: explicitly set projectId if needed:
  // projectId: 'your-project-id',
});

async function setAdmin(uid) {
  try {
    await admin.auth().setCustomUserClaims(uid, { admin: true });
    console.log('✅ Set admin claim for', uid);
    process.exit(0);
  } catch (err) {
    console.error('❌ Error setting admin claim:', err);
    process.exit(1);
  }
}

// Replace with the UID of the distributor/admin user, or pass it as an argument
const uidArg = process.argv[2];
if (!uidArg) {
  console.error('Usage: node setAdminClaim.js <UID_OF_USER>');
  process.exit(2);
}
setAdmin(uidArg);
