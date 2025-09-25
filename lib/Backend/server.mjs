// backend/server.mjs
import express from 'express';
import cors from 'cors';
import fetch from 'node-fetch';

const USERNAME = '505679';
const PASSWORD = 'lmtdbtdq';
const A1_BASE = 'https://business.a1topup.com/recharge/api';

const app = express();
app.use(cors());
app.use(express.json());

app.post('/recharge', async (req, res) => {
  const { number, amount, operatorCode, circleCode, orderId } = req.body;
  if (!number || !amount || !operatorCode || !circleCode || !orderId) {
    return res.status(400).json({ status: 'Failure', message: 'Missing params' });
  }

  try {
    const url = new URL(A1_BASE);
    url.searchParams.set('username', USERNAME);
    url.searchParams.set('pwd', PASSWORD);
    url.searchParams.set('circlecode', circleCode);
    url.searchParams.set('operatorcode', operatorCode);
    url.searchParams.set('number', number);
    url.searchParams.set('amount', amount);
    url.searchParams.set('orderid', orderId);
    url.searchParams.set('format', 'json');

    const r = await fetch(url.toString());
    const rawText = await r.text();

    let response;
    try {
        response = JSON.parse(rawText);
    } catch (e) {
        return res.status(400).json({ status: 'Failure', message: rawText });
    }

    if (response.status && (response.status.toLowerCase() === 'success')) {
      return res.status(200).json({ status: 'Success', message: 'Recharge successful', api_status: response.status });
    } else if (response.status && response.status.toLowerCase() === 'pending') {
      return res.status(200).json({ status: 'Success', message: 'Recharge sent successfully', api_status: response.status });
    } else {
      return res.status(400).json({ status: 'Failure', message: response.message || 'Recharge failed' });
    }
  } catch (error) {
    return res.status(500).json({ status: 'Failure', message: 'Error processing payment', error: error.message });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`Server running on http://localhost:${PORT}`));