import http from 'node:http';
import { Catalog } from '../src/catalog.js';
import { loadConfig } from '../src/config.js';
import { createServer } from '../src/server.js';
import { Store } from '../src/store.js';
import { signWebhook } from '../src/stripe.js';

export const WEBHOOK_SECRET = 'whsec_test_secret';
export const ADDRESS = { line1: '1 Market St', city: 'San Francisco', state: 'CA', postalCode: '94105', country: 'US' };

/** Stripe API 흉내: 고객·카드·PaymentIntent·멱등 키만 구현한다. */
export async function startFakeStripe() {
  const state = { customers: [], intents: new Map(), idempotent: new Map(), calls: [], seq: 0 };
  const server = http.createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    const params = new URLSearchParams(req.method === 'GET' ? req.url.split('?')[1] ?? '' : body);
    const path = req.url.split('?')[0];
    state.calls.push(`${req.method} ${path}`);
    const reply = (status, json) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(json)); };
    const key = req.headers['idempotency-key'];
    if (key && state.idempotent.has(key)) return reply(200, state.idempotent.get(key));
    const remember = (json) => { if (key) state.idempotent.set(key, json); return reply(200, json); };
    if (req.headers.authorization !== 'Bearer sk_test_fake') return reply(401, { error: { message: 'bad key' } });
    if (path === '/v1/customers') { const c = { id: `cus_${++state.seq}` }; state.customers.push(c); return remember(c); }
    if (/^\/v1\/payment_methods\/.+\/attach$/.test(path)) return reply(200, { id: 'pm_1' });
    if (path === '/v1/payment_methods') return reply(200, { data: [{ id: 'pm_1', card: { brand: 'visa', last4: '4242' } }] });
    if (path === '/v1/ephemeral_keys') return reply(200, { secret: `ek_test_${++state.seq}` });
    if (path === '/v1/payment_intents' && req.method === 'POST') {
      const intent = {
        id: `pi_${++state.seq}`, status: 'requires_payment_method', client_secret: `pi_secret_${state.seq}`,
        amount: Number(params.get('amount')), currency: params.get('currency'), description: params.get('description'),
        customer: params.get('customer'), metadata: { order_id: params.get('metadata[order_id]'), test: params.get('metadata[test]') },
      };
      state.intents.set(intent.id, intent);
      return remember(intent);
    }
    const match = path.match(/^\/v1\/payment_intents\/(pi_\d+)(\/cancel)?$/);
    const intent = match && state.intents.get(match[1]);
    if (!intent) return reply(404, { error: { message: 'No such payment_intent' } });
    if (match[2]) {
      if (intent.status === 'succeeded') return reply(400, { error: { message: 'cannot cancel succeeded' } });
      intent.status = 'canceled';
    }
    return reply(200, intent);
  });
  await new Promise((resolve) => server.listen(0, resolve));
  return { state, url: `http://127.0.0.1:${server.address().port}`, close: () => server.close() };
}

export async function startApp({ catalogMutator } = {}) {
  const stripe = await startFakeStripe();
  const config = loadConfig({
    STRIPE_SECRET_KEY: 'sk_test_fake', STRIPE_WEBHOOK_SECRET: WEBHOOK_SECRET, STRIPE_API_BASE: stripe.url, DATA_FILE: '',
  });
  const catalog = Catalog.load(config.catalogPath);
  catalogMutator?.(catalog);
  const app = createServer({ config, catalog, store: new Store(null) });
  await new Promise((resolve) => app.server.listen(0, resolve));
  const base = `http://127.0.0.1:${app.server.address().port}`;

  const call = async (method, path, { token, body, headers } = {}) => {
    const response = await fetch(base + path, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };
  const register = async () => (await call('POST', '/v1/devices', { body: { name: 'Harper', address: ADDRESS } })).body.token;
  const webhook = (type, intent, { id = `evt_${stripe.state.seq++}_${Math.random()}`, secret = WEBHOOK_SECRET, timestamp } = {}) => {
    const payload = JSON.stringify({ id, type, data: { object: intent } });
    return call('POST', '/webhooks/stripe', { body: payload, headers: { 'stripe-signature': signWebhook(payload, secret, timestamp) } });
  };
  return {
    app, stripe, call, register, webhook, catalog, base,
    close: () => { app.server.close(); stripe.close(); },
  };
}
