import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { loadConfig } from '../src/config.js';
import { signWebhook } from '../src/stripe.js';
import { startApp } from './helpers.js';

let t;
before(async () => { t = await startApp(); });
after(() => t.close());

/** 견적 → 주문 확인까지 진행해 결제 직전 상태를 만든다. */
async function checkout(productId = 'sofa_028_brown', budgetCents = 20_000_00) {
  const token = await t.register();
  const quote = await t.call('POST', '/v1/quotes', { token, body: { productId, quantity: 1, budgetCents } });
  assert.equal(quote.body.status, 'ok', JSON.stringify(quote.body));
  return { token, orderId: quote.body.orderId, quote: quote.body.quote };
}
const confirm = (c) => t.call('POST', `/v1/orders/${c.orderId}/confirm`, { token: c.token, body: { quoteHash: c.quote.hash } });
const intentOf = (orderId) => [...t.stripe.state.intents.values()].filter((i) => i.metadata.order_id === orderId);

describe('quote', () => {
  it('computes price + shipping + tax from catalog data and ignores client-sent amounts', async () => {
    const token = await t.register();
    const { body } = await t.call('POST', '/v1/quotes', {
      token, body: { productId: 'sofa_024_beige', quantity: 2, budgetCents: 200_000, totalCents: 1, priceCents: 1, amount: 1 },
    });
    // 14900 * 2 = 29800; no catalog shipping fee → flat 2999; CA 8.75% of 29800 = 2607.5 → 2608
    assert.equal(body.status, 'ok');
    assert.equal(body.quote.subtotalCents, 29_800);
    assert.equal(body.quote.shippingCents, 2_999);
    assert.equal(body.quote.taxCents, 2_608);
    assert.equal(body.quote.totalCents, 29_800 + 2_999 + 2_608);
    assert.equal(body.quote.test, true);
    assert.deepEqual(body.paymentMethod, { brand: 'visa', last4: '4242' });
  });

  it('uses the catalog shipping fee when present (free shipping)', async () => {
    const token = await t.register();
    const { body } = await t.call('POST', '/v1/quotes', { token, body: { productId: 'sofa_030_yaheetech_x', quantity: 1 } });
    assert.equal(body.error, 'unknown_product');
    const real = [...t.catalog.products].find((p) => p.shippingFeeCents === 0);
    const ok = await t.call('POST', '/v1/quotes', { token, body: { productId: real.id, quantity: 1 } });
    assert.equal(ok.body.quote.shippingCents, 0);
  });

  it('suggests in-budget alternatives that keep category, placement footprint and style', async () => {
    const token = await t.register();
    const { body } = await t.call('POST', '/v1/quotes', { token, body: { productId: 'sofa_012_brown', quantity: 1, budgetCents: 20_000 } });
    assert.equal(body.status, 'over_budget');
    assert.equal(body.orderId, undefined, 'no order is created for an over-budget quote');
    assert.ok(body.alternatives.length > 0 && body.alternatives.length <= 3);
    const original = t.catalog.get('sofa_012_brown');
    for (const alt of body.alternatives) {
      const product = t.catalog.get(alt.product.id);
      assert.equal(product.category, original.category);
      assert.ok(alt.totalCents <= 20_000, `${alt.product.id} total ${alt.totalCents}`);
      assert.equal(product.availability, 'in_stock');
    }
    // 자리에 들어가는 대안이 먼저 나온다.
    const flags = body.alternatives.map((a) => a.fitsPlacement);
    assert.deepEqual(flags, [...flags].sort((a, b) => b - a));
    assert.ok(body.alternatives[0].fitsPlacement);
  });

  it('refuses items that are not in stock and offers alternatives', async () => {
    const token = await t.register();
    const { body } = await t.call('POST', '/v1/quotes', { token, body: { productId: 'sofa_007_brown', quantity: 1 } });
    assert.equal(body.status, 'unavailable');
    assert.ok(body.alternatives.length > 0);
    const confirmAttempt = await t.call('POST', `/v1/orders/${body.orderId}/confirm`, { token, body: {} });
    assert.equal(confirmAttempt.status, 404);
  });

  it('rejects bad quantities, unknown products and incomplete profiles', async () => {
    const token = await t.register();
    for (const quantity of [0, 99, 1.5]) {
      const r = await t.call('POST', '/v1/quotes', { token, body: { productId: 'sofa_028_brown', quantity } });
      assert.equal(r.body.error, 'invalid_quantity');
    }
    const noAddress = await t.call('POST', '/v1/devices', { body: { name: 'x' } });
    assert.equal(noAddress.status, 422);
  });
});

describe('payment success', () => {
  it('creates one TEST-labelled PaymentIntent for the server total and marks paid only via signed webhook', async () => {
    const c = await checkout();
    const result = await confirm(c);
    assert.equal(result.status, 200);
    assert.equal(result.body.status, 'awaiting_payment');
    assert.ok(result.body.payment.clientSecret.startsWith('pi_secret_'));
    assert.ok(result.body.payment.ephemeralKeySecret.startsWith('ek_test_'));
    const [intent] = intentOf(c.orderId);
    assert.equal(intent.amount, c.quote.totalCents);
    assert.match(intent.description, /^\[TEST\]/);
    assert.equal(intent.metadata.test, 'true');

    // PaymentSheet이 끝났다고 해도 웹훅 전에는 paid가 아니다.
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'awaiting_payment');
    intent.status = 'succeeded';
    const hook = await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount });
    assert.equal(hook.body.result, 'paid');
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'paid');
  });
});

describe('payment decline', () => {
  it('records the decline from the webhook, then lets the user retry on the same PaymentIntent', async () => {
    const c = await checkout();
    const first = await confirm(c);
    const [intent] = intentOf(c.orderId);
    await t.webhook('payment_intent.payment_failed', {
      ...intent, last_payment_error: { code: 'card_declined', decline_code: 'generic_decline', message: 'Your card was declined.' },
    });
    const failed = (await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body;
    assert.equal(failed.status, 'payment_failed');
    assert.equal(failed.failure.declineCode, 'generic_decline');
    assert.equal(failed.failure.message, 'Your card was declined.');

    const retry = await confirm(c);
    assert.equal(retry.body.status, 'awaiting_payment');
    assert.equal(retry.body.payment.clientSecret, first.body.payment.clientSecret);
    assert.equal(intentOf(c.orderId).length, 1, 'retry reuses the PaymentIntent');

    await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount });
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'paid');
  });

  it('does not let a late failure event undo a successful payment', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount });
    await t.webhook('payment_intent.payment_failed', intent);
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'paid');
  });
});

describe('cancellation', () => {
  it('cancels the PaymentIntent and blocks further payment', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    const canceled = await t.call('POST', `/v1/orders/${c.orderId}/cancel`, { token: c.token });
    assert.equal(canceled.body.status, 'canceled');
    assert.equal(intent.status, 'canceled');
    assert.equal((await t.call('POST', `/v1/orders/${c.orderId}/cancel`, { token: c.token })).body.status, 'canceled', 'cancel is idempotent');
    const again = await confirm(c);
    assert.equal(again.status, 409);
    assert.equal(again.body.error, 'order_canceled');
  });

  it('cannot cancel an order that is already paid', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    intent.status = 'succeeded';
    await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount });
    const r = await t.call('POST', `/v1/orders/${c.orderId}/cancel`, { token: c.token });
    assert.equal(r.status, 409);
    assert.equal(r.body.error, 'already_paid');
  });

  it('keeps the order payable if Stripe says the payment already succeeded (webhook pending)', async () => {
    const c = await checkout();
    await confirm(c);
    intentOf(c.orderId)[0].status = 'succeeded';
    const r = await t.call('POST', `/v1/orders/${c.orderId}/cancel`, { token: c.token });
    assert.equal(r.status, 409);
    assert.equal(r.body.error, 'payment_processing');
  });
});

describe('duplicate requests', () => {
  it('concurrent double-tap confirms create exactly one PaymentIntent', async () => {
    const c = await checkout();
    const [a, b, d] = await Promise.all([confirm(c), confirm(c), confirm(c)]);
    assert.equal(intentOf(c.orderId).length, 1);
    assert.equal(a.body.payment.clientSecret, b.body.payment.clientSecret);
    assert.equal(a.body.payment.clientSecret, d.body.payment.clientSecret);
  });

  it('sequential repeat confirms return the same PaymentIntent', async () => {
    const c = await checkout();
    const first = await confirm(c);
    const second = await confirm(c);
    assert.equal(first.body.payment.clientSecret, second.body.payment.clientSecret);
    assert.equal(intentOf(c.orderId).length, 1);
  });

  it('confirming an already paid order is a no-op', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount });
    const before = t.stripe.state.intents.size;
    const again = await confirm(c);
    assert.equal(again.body.status, 'paid');
    assert.equal(again.body.payment, undefined);
    assert.equal(t.stripe.state.intents.size, before);
  });

  it('processes a redelivered webhook event only once', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    const first = await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount }, { id: 'evt_same' });
    const second = await t.webhook('payment_intent.succeeded', { ...intent, amount_received: intent.amount }, { id: 'evt_same' });
    assert.equal(first.body.result, 'paid');
    assert.equal(second.body.result, 'duplicate');
  });
});

describe('quote changes are reconfirmed', () => {
  it('returns 409 with the new quote when the server price changed, and charges the new total after reconfirm', async () => {
    const c = await checkout();
    t.catalog.get('sofa_028_brown').priceCents += 1_000;
    const changed = await confirm(c);
    assert.equal(changed.status, 409);
    assert.equal(changed.body.error, 'quote_changed');
    assert.equal(changed.body.quote.unitCents, c.quote.unitCents + 1_000);
    assert.notEqual(changed.body.quote.hash, c.quote.hash);
    assert.equal(intentOf(c.orderId).length, 0, 'no payment is created for an unapproved quote');

    const stillOld = await confirm(c); // 옛 견적 해시로는 계속 거부
    assert.equal(stillOld.status, 409);
    const approved = await t.call('POST', `/v1/orders/${c.orderId}/confirm`, { token: c.token, body: { quoteHash: changed.body.quote.hash } });
    assert.equal(approved.status, 200);
    assert.equal(intentOf(c.orderId)[0].amount, changed.body.quote.totalCents);
    t.catalog.get('sofa_028_brown').priceCents -= 1_000;
  });

  it('refuses to charge when the new total exceeds the budget or the item sold out', async () => {
    const c = await checkout('sofa_028_brown', 50_000);
    const product = t.catalog.get('sofa_028_brown');
    product.priceCents = 49_000;
    const over = await confirm(c);
    assert.equal(over.status, 409);
    assert.equal(over.body.error, 'over_budget');
    product.priceCents = 41_999;
    product.availability = 'out_of_stock';
    const gone = await confirm(c);
    assert.equal(gone.body.error, 'unavailable');
    product.availability = 'in_stock';
    assert.equal(intentOf(c.orderId).length, 0);
  });

  it('cancels the old PaymentIntent if the quote changes after a payment was prepared', async () => {
    const c = await checkout();
    await confirm(c);
    const [old] = intentOf(c.orderId);
    t.catalog.get('sofa_028_brown').priceCents += 500;
    const changed = await confirm(c);
    assert.equal(changed.status, 409);
    assert.equal(old.status, 'canceled');
    t.catalog.get('sofa_028_brown').priceCents -= 500;
  });
});

describe('ownership and auth', () => {
  it('hides other devices\' orders and requires a token', async () => {
    const c = await checkout();
    const stranger = await t.register();
    for (const [method, path] of [['GET', ''], ['POST', '/confirm'], ['POST', '/cancel']]) {
      const r = await t.call(method, `/v1/orders/${c.orderId}${path}`, { token: stranger, body: method === 'POST' ? { quoteHash: c.quote.hash } : undefined });
      assert.equal(r.status, 404, `${method} ${path}`);
    }
    assert.equal(intentOf(c.orderId).length, 0);
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`)).status, 401);
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: 'bogus' })).status, 401);
  });
});

describe('webhook security', () => {
  const payload = (intent) => JSON.stringify({ id: `evt_${Math.random()}`, type: 'payment_intent.succeeded', data: { object: intent } });

  it('rejects missing, wrong and stale signatures without changing the order', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    const body = payload({ ...intent, amount_received: intent.amount });
    const secrets = [
      {},
      { 'stripe-signature': signWebhook(body, 'whsec_wrong') },
      { 'stripe-signature': signWebhook(body, 'whsec_test_secret', Math.floor(Date.now() / 1000) - 3600) },
      { 'stripe-signature': signWebhook(body + ' ', 'whsec_test_secret') },
    ];
    for (const headers of secrets) {
      const r = await t.call('POST', '/webhooks/stripe', { body, headers });
      assert.equal(r.status, 400);
    }
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'awaiting_payment');
  });

  it('does not mark paid when the charged amount differs from the server quote', async () => {
    const c = await checkout();
    await confirm(c);
    const [intent] = intentOf(c.orderId);
    const hook = await t.webhook('payment_intent.succeeded', { ...intent, amount: 100 });
    assert.equal(hook.body.result, 'amount_mismatch');
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'needs_review');
  });

  it('ignores events for PaymentIntents the order no longer uses', async () => {
    const c = await checkout();
    const hook = await t.webhook('payment_intent.succeeded', { id: 'pi_other', amount: 1, currency: 'usd', metadata: { order_id: c.orderId } });
    assert.equal(hook.body.result, 'stale');
    assert.equal((await t.call('GET', `/v1/orders/${c.orderId}`, { token: c.token })).body.status, 'quoted');
  });
});

describe('config', () => {
  it('refuses live keys and missing webhook secrets', () => {
    assert.throws(() => loadConfig({ STRIPE_SECRET_KEY: 'sk_live_x', STRIPE_WEBHOOK_SECRET: 'whsec_x' }), /TEST key/);
    assert.throws(() => loadConfig({ STRIPE_SECRET_KEY: 'sk_test_x' }), /WEBHOOK_SECRET/);
  });
});
