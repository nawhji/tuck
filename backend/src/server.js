import http from 'node:http';
import { loadConfig, loadDotEnv } from './config.js';
import { Catalog } from './catalog.js';
import { Orders } from './orders.js';
import { QuoteError } from './quote.js';
import { Store } from './store.js';
import { Stripe, StripeError, verifyWebhook } from './stripe.js';

const MAX_BODY = 64 * 1024;

function readBody(request) {
  return new Promise((resolve, reject) => {
    let body = '';
    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > MAX_BODY) { reject(new QuoteError('too_large', 'Request body too large.', 413)); request.destroy(); }
    });
    request.on('end', () => resolve(body));
    request.on('error', reject);
  });
}

const send = (response, status, body) => {
  response.writeHead(status, { 'content-type': 'application/json' });
  response.end(JSON.stringify(body));
};

export function createServer({ config, store = new Store(config.dataFile), catalog = Catalog.load(config.catalogPath),
  stripe = new Stripe({ secretKey: config.stripeSecretKey, apiBase: config.stripeApiBase }) }) {
  const orders = new Orders({ config, store, catalog, stripe });

  async function route(request, response) {
    const url = new URL(request.url, 'http://localhost');
    const raw = request.method === 'POST' ? await readBody(request) : '';

    // 웹훅은 원문 바디로 서명을 검증하며, 앱 토큰 인증과 무관하다.
    if (request.method === 'POST' && url.pathname === '/webhooks/stripe') {
      if (!verifyWebhook(raw, request.headers['stripe-signature'], config.webhookSecret)) {
        return send(response, 400, { error: 'invalid_signature' });
      }
      let event;
      try { event = JSON.parse(raw); } catch { return send(response, 400, { error: 'invalid_json' }); }
      return send(response, 200, { received: true, result: orders.applyEvent(event) });
    }

    let json = {};
    try { json = raw ? JSON.parse(raw) : {}; } catch { throw new QuoteError('invalid_json', 'Body must be JSON.'); }

    if (request.method === 'POST' && url.pathname === '/v1/devices') {
      return send(response, 201, await orders.registerDevice(json));
    }

    const device = orders.authenticate(request.headers.authorization?.replace(/^Bearer /, ''));
    if (!device) throw new QuoteError('unauthorized', 'Missing or invalid token.', 401);

    if (request.method === 'POST' && url.pathname === '/v1/quotes') {
      const budgetCents = json.budgetCents ?? null;
      return send(response, 200, await orders.createQuote(device, { productId: json.productId, quantity: json.quantity ?? 1, budgetCents }));
    }
    const match = url.pathname.match(/^\/v1\/orders\/([\w-]+)(?:\/(confirm|cancel))?$/);
    if (match) {
      const [, id, action] = match;
      if (request.method === 'GET' && !action) return send(response, 200, await orders.getOrder(device, id));
      if (request.method === 'POST' && action === 'confirm') {
        const result = await orders.confirm(device, id, json.quoteHash);
        return send(response, result.changed ? 409 : 200, result.changed ? { error: 'quote_changed', ...result } : result);
      }
      if (request.method === 'POST' && action === 'cancel') return send(response, 200, await orders.cancel(device, id));
    }
    throw new QuoteError('not_found', 'Not found.', 404);
  }

  const server = http.createServer((request, response) => {
    route(request, response).catch((error) => {
      if (error instanceof QuoteError) return send(response, error.status, { error: error.code, message: error.message });
      console.error(error instanceof StripeError ? `Stripe: ${error.message}` : error);
      return send(response, 500, { error: 'server_error', message: 'Something went wrong. Please try again.' });
    });
  });
  return { server, orders, store };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  loadDotEnv();
  const config = loadConfig();
  createServer({ config }).server.listen(config.port, () => console.log(`Tuck backend (Stripe TEST mode) on :${config.port}`));
}
