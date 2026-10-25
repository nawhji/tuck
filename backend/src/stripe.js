import crypto from 'node:crypto';

export class StripeError extends Error {
  constructor(status, body) {
    super(body?.error?.message ?? `Stripe error ${status}`);
    this.status = status;
    this.code = body?.error?.code;
  }
}

/** Stripe REST 호출용 폼 인코딩: {a:{b:1}} → a[b]=1 */
export function encodeForm(params, prefix = '') {
  const pairs = [];
  for (const [key, value] of Object.entries(params)) {
    if (value == null) continue;
    const name = prefix ? `${prefix}[${key}]` : key;
    if (typeof value === 'object') pairs.push(...encodeForm(value, name));
    else pairs.push(`${encodeURIComponent(name)}=${encodeURIComponent(String(value))}`);
  }
  return pairs;
}

/** 외부 SDK 없이 쓰는 최소 Stripe 클라이언트. 비밀 키는 서버에서만 사용한다. */
export class Stripe {
  constructor({ secretKey, apiBase }) {
    this.secretKey = secretKey;
    this.apiBase = apiBase;
  }

  async request(method, path, params = {}, { idempotencyKey, version } = {}) {
    const query = method === 'GET' ? encodeForm(params).join('&') : '';
    const response = await fetch(`${this.apiBase}${path}${query ? `?${query}` : ''}`, {
      method,
      headers: {
        authorization: `Bearer ${this.secretKey}`,
        ...(method === 'GET' ? {} : { 'content-type': 'application/x-www-form-urlencoded' }),
        ...(idempotencyKey ? { 'idempotency-key': idempotencyKey } : {}),
        ...(version ? { 'stripe-version': version } : {}),
      },
      body: method === 'GET' ? undefined : encodeForm(params).join('&'),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new StripeError(response.status, body);
    return body;
  }

  createCustomer(params, idempotencyKey) { return this.request('POST', '/v1/customers', params, { idempotencyKey }); }
  attachPaymentMethod(id, customer) { return this.request('POST', `/v1/payment_methods/${id}/attach`, { customer }); }
  listCards(customer) { return this.request('GET', '/v1/payment_methods', { customer, type: 'card', limit: 1 }); }
  createEphemeralKey(customer) {
    return this.request('POST', '/v1/ephemeral_keys', { customer }, { version: '2024-06-20' });
  }
  createPaymentIntent(params, idempotencyKey) { return this.request('POST', '/v1/payment_intents', params, { idempotencyKey }); }
  retrievePaymentIntent(id) { return this.request('GET', `/v1/payment_intents/${id}`); }
  cancelPaymentIntent(id) { return this.request('POST', `/v1/payment_intents/${id}/cancel`); }
}

/** Stripe-Signature(t=…,v1=…) 검증. 원문 바디와 서명 비밀로 HMAC을 계산하고 허용 시간차를 확인한다. */
export function verifyWebhook(rawBody, header, secret, { toleranceSeconds = 300, now = () => Date.now() / 1000 } = {}) {
  const parts = String(header ?? '').split(',').map((p) => p.trim().split('='));
  const timestamp = parts.find(([k]) => k === 't')?.[1];
  const signatures = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!timestamp || signatures.length === 0) return false;
  if (Math.abs(now() - Number(timestamp)) > toleranceSeconds) return false;
  const expected = crypto.createHmac('sha256', secret).update(`${timestamp}.${rawBody}`).digest();
  return signatures.some((sig) => {
    const given = Buffer.from(sig, 'hex');
    return given.length === expected.length && crypto.timingSafeEqual(given, expected);
  });
}

export function signWebhook(rawBody, secret, timestamp = Math.floor(Date.now() / 1000)) {
  const sig = crypto.createHmac('sha256', secret).update(`${timestamp}.${rawBody}`).digest('hex');
  return `t=${timestamp},v1=${sig}`;
}
