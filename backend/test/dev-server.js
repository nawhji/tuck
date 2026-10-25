// Integration test server for the app client: runs the backend with mock Stripe and exposes a control port for webhooks and price changes.
// Run: node backend/test/dev-server.js (prints the {"base","control"} URLs as JSON to stdout)
import http from 'node:http';
import { startApp } from './helpers.js';

const t = await startApp();
const intentFor = (orderId) => [...t.stripe.state.intents.values()].find((i) => i.metadata.order_id === orderId);

const control = http.createServer(async (req, res) => {
  let body = '';
  for await (const chunk of req) body += chunk;
  const { type, orderId, productId, cents, status, failure } = body ? JSON.parse(body) : {};
  let result = { ok: true };
  if (req.url === '/event') {
    const intent = intentFor(orderId);
    if (status) intent.status = status;
    result = (await t.webhook(type, { ...intent, amount_received: intent.amount, last_payment_error: failure })).body;
  } else if (req.url === '/price') {
    t.catalog.get(productId).priceCents = cents;
  } else if (req.url === '/intents') {
    result = { count: t.stripe.state.intents.size };
  }
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify(result));
});
await new Promise((resolve) => control.listen(0, resolve));
console.log(JSON.stringify({ base: t.base, control: `http://127.0.0.1:${control.address().port}` }));
