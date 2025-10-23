// index.mjs
import express from 'express';
import axios from 'axios';
import cors from 'cors';

const app = express();
app.use(express.json());
app.use(cors()); // allow cross-origin requests from your app/dev tools

const QPayAPIKey = 'cmHWJAgCbgMmvbqAmvA6J9NyfjezT1wTTD/bv2gCLxoHleP0yikH';
const QPayID = 'OSGEapiacc';
const QPayPWD = 'OSGE!123';

app.post('/addMoney', async (req, res) => {
  console.log('[Server] Received request:', req.body);

  const { amount, userId } = req.body;
  if (!amount) {
    return res.status(400).json({ success: false, message: 'amount required' });
  }

  try {
    // Example request to QPay. Adjust the URL + payload to match QPay docs.
    const qpayResponse = await axios.post(
      'https://qpay.api.url/your-endpoint', // <-- REPLACE with real QPay endpoint
      {
        user_id: QPayID,
        password: QPayPWD,
        amount: amount,
        // add other required fields here
      },
      {
        headers: {
          'Authorization': `Bearer ${QPayAPIKey}`,
          'Content-Type': 'application/json'
        },
        timeout: 20000 // 20s axios timeout for QPay call
      }
    );

    console.log('[Server] QPay response:', qpayResponse.data);

    // adapt success check to QPay response shape:
    if (qpayResponse.data && qpayResponse.data.status === 'success') {
      return res.status(200).json({ success: true, message: 'Amount added successfully!' });
    }

    return res.status(400).json({ success: false, message: 'Payment failed', detail: qpayResponse.data });

  } catch (err) {
    console.error('[Server] Payment error:', err && err.toString ? err.toString() : err);
    // Send back useful info for debugging (remove sensitive details in production)
    return res.status(500).json({ success: false, message: 'Server error contacting QPay', error: err.message || err.toString() });
  }
});

// listen on all interfaces so external devices can connect
app.listen(3000, '0.0.0.0', () => {
  console.log('Server is running on port 3000 (listening on 0.0.0.0)');
});
