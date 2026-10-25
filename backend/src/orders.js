import crypto from 'node:crypto';
import { buildQuote, QuoteError, quoteHash } from './quote.js';
import { StripeError } from './stripe.js';

const REUSABLE_PI = new Set(['requires_payment_method', 'requires_confirmation', 'requires_action', 'processing']);
const ADDRESS_FIELDS = ['line1', 'city', 'state', 'postalCode', 'country'];
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

/** Order and payment logic. Amount, inventory, and ownership decisions use server data only. */
export class Orders {
  constructor({ config, store, catalog, stripe }) {
    Object.assign(this, { config, store, catalog, stripe });
    this.locks = new Map();
  }

  /** Serializes requests for the same order (prevents double taps and retry races). */
  async withLock(orderId, work) {
    const previous = this.locks.get(orderId) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(work);
    const tail = run.catch(() => {});
    this.locks.set(orderId, tail);
    try { return await run; } finally { if (this.locks.get(orderId) === tail) this.locks.delete(orderId); }
  }

  // MARK: Devices

  /** Without sign-in, create an anonymous token and Stripe Customer per device. The profile screen supplies the address later. */
  async registerDevice(profile) {
    const address = validateAddress(profile?.address);
    const id = `dev_${crypto.randomUUID()}`;
    const token = crypto.randomBytes(32).toString('base64url');
    const customer = await this.stripe.createCustomer(
      { name: profile?.name, description: 'Tuck TEST customer', metadata: { device_id: id, test: 'true' } },
      `tuck-customer-${id}`,
    );
    if (this.config.seedTestPaymentMethod) {
      await this.stripe.attachPaymentMethod('pm_card_visa', customer.id);
    }
    this.store.data.devices[sha256(token)] = { id, customerId: customer.id, profile: { name: profile?.name ?? '', address } };
    this.store.save();
    return { token, deviceId: id };
  }

  authenticate(token) {
    return token ? this.store.data.devices[sha256(token)] ?? null : null;
  }

  async paymentMethodSummary(device) {
    try {
      const card = (await this.stripe.listCards(device.customerId)).data?.[0]?.card;
      return card ? { brand: card.brand, last4: card.last4 } : null;
    } catch { return null; }
  }

  // MARK: Quotes

  async createQuote(device, { productId, quantity = 1, budgetCents = null }) {
    const result = buildQuote({
      catalog: this.catalog, secret: this.config.quoteSecret, ownerId: device.id, productId, quantity,
      address: device.profile.address, budgetCents,
    });
    const paymentMethod = await this.paymentMethodSummary(device);
    if (result.status !== 'ok') return { ...result, paymentMethod };
    if (result.quote.totalCents > this.config.maxOrderCents) {
      throw new QuoteError('over_limit', 'This order is above the per-order test limit.', 422);
    }
    const order = {
      id: `ord_${crypto.randomUUID()}`, ownerId: device.id, status: 'quoted', quote: result.quote,
      paymentIntentId: null, attempt: 0, failure: null, createdAt: Date.now(),
    };
    this.store.data.orders[order.id] = order;
    this.store.save();
    return { status: 'ok', orderId: order.id, quote: order.quote, alternatives: [], paymentMethod };
  }

  /** Do not reveal whether an order exists if the caller is not its owner. */
  ownedOrder(device, orderId) {
    const order = this.store.data.orders[orderId];
    if (!order || order.ownerId !== device.id) throw new QuoteError('order_not_found', 'Order not found.', 404);
    return order;
  }

  async getOrder(device, orderId) {
    const order = this.ownedOrder(device, orderId);
    await this.reconcile(order);
    return this.view(order, await this.paymentMethodSummary(device));
  }

  view(order, paymentMethod = null) {
    return { orderId: order.id, status: order.status, quote: order.quote, failure: order.failure, paymentMethod };
  }

  // MARK: Confirm / cancel

  confirm(device, orderId, approvedHash) {
    this.ownedOrder(device, orderId);
    return this.withLock(orderId, () => this.confirmLocked(device, orderId, approvedHash));
  }

  async confirmLocked(device, orderId, approvedHash) {
    const order = this.ownedOrder(device, orderId);
    if (order.status === 'paid') return this.view(order);
    if (order.status === 'canceled') throw new QuoteError('order_canceled', 'This order was canceled.', 409);

    // Recalculate the quote from trusted current data. Ask for confirmation again if it changed or differs from what the user saw.
    const fresh = buildQuote({
      catalog: this.catalog, secret: this.config.quoteSecret, ownerId: device.id, productId: order.quote.product.id,
      quantity: order.quote.quantity, address: device.profile.address, budgetCents: order.quote.budgetCents,
    });
    if (fresh.status !== 'ok') {
      throw new QuoteError(fresh.status, fresh.status === 'unavailable' ? 'This item is no longer available.' : 'The price is now above your budget.', 409);
    }
    if (fresh.quote.hash !== order.quote.hash || approvedHash !== order.quote.hash) {
      if (fresh.quote.hash !== order.quote.hash) await this.replaceQuote(order, fresh.quote);
      return { ...this.view(order, await this.paymentMethodSummary(device)), changed: true };
    }
    if (order.quote.totalCents > this.config.maxOrderCents) {
      throw new QuoteError('over_limit', 'This order is above the per-order test limit.', 422);
    }

    const intent = await this.paymentIntentFor(order, device);
    const key = await this.stripe.createEphemeralKey(device.customerId);
    order.status = 'awaiting_payment';
    order.failure = null;
    this.store.save();
    return {
      ...this.view(order, await this.paymentMethodSummary(device)),
      payment: { clientSecret: intent.client_secret, customerId: device.customerId, ephemeralKeySecret: key.secret },
    };
  }

  /** If the quote changes, discard the old PaymentIntent and return the order to confirmation pending. */
  async replaceQuote(order, quote) {
    const stale = order.paymentIntentId;
    order.paymentIntentId = null;
    order.quote = quote;
    order.status = 'quoted';
    order.failure = null;
    this.store.save();
    if (stale) await this.stripe.cancelPaymentIntent(stale).catch(() => {});
  }

  /** Include the per-order attempt number in the idempotency key so retries of one attempt create only one PaymentIntent. */
  async paymentIntentFor(order, device) {
    if (order.paymentIntentId) {
      const existing = await this.stripe.retrievePaymentIntent(order.paymentIntentId);
      if (REUSABLE_PI.has(existing.status) && existing.amount === order.quote.totalCents) return existing;
      if (existing.status === 'succeeded') throw new QuoteError('payment_processing', 'Payment already went through; waiting for confirmation.', 409);
      order.attempt += 1;
    }
    const intent = await this.stripe.createPaymentIntent({
      amount: order.quote.totalCents,
      currency: order.quote.currency,
      customer: device.customerId,
      automatic_payment_methods: { enabled: true },
      description: `[TEST] Tuck order ${order.id} (Stripe test mode, no real charge)`,
      metadata: { order_id: order.id, quote_hash: order.quote.hash, test: 'true' },
    }, `tuck-pi-${order.id}-${order.attempt}`);
    order.paymentIntentId = intent.id;
    this.store.save();
    return intent;
  }

  cancel(device, orderId) {
    this.ownedOrder(device, orderId);
    return this.withLock(orderId, async () => {
      const order = this.ownedOrder(device, orderId);
      if (order.status === 'paid') throw new QuoteError('already_paid', 'This order is already paid.', 409);
      if (order.status !== 'canceled' && order.paymentIntentId) {
        try {
          await this.stripe.cancelPaymentIntent(order.paymentIntentId);
        } catch (error) {
          // A completed payment cannot be canceled. The webhook determines the final status.
          if (!(error instanceof StripeError)) throw error;
          const current = await this.stripe.retrievePaymentIntent(order.paymentIntentId);
          if (current.status === 'succeeded' || current.status === 'processing') {
            throw new QuoteError('payment_processing', 'Payment is already being processed.', 409);
          }
        }
      }
      order.status = 'canceled';
      this.store.save();
      return this.view(order);
    });
  }

  /** If a webhook has not arrived or was lost (for example, during local development), confirm pending orders using the status retrieved from Stripe. */
  async reconcile(order) {
    if (order.status !== 'awaiting_payment' || !order.paymentIntentId) return;
    await this.withLock(order.id, async () => {
      if (order.status !== 'awaiting_payment') return;
      let intent;
      try { intent = await this.stripe.retrievePaymentIntent(order.paymentIntentId); } catch { return; }
      const type = {
        succeeded: 'payment_intent.succeeded',
        canceled: 'payment_intent.canceled',
        requires_payment_method: intent.last_payment_error ? 'payment_intent.payment_failed' : null,
      }[intent.status];
      if (!type) return;
      this.applyPaymentEvent({ type, data: { object: { ...intent, metadata: { ...intent.metadata, order_id: order.id } } } });
      this.store.save();
    });
  }

  // MARK: Webhook

  /** Only verified events arrive here. Duplicate events, stale PaymentIntents, and out-of-order events must not corrupt state. */
  applyEvent(event) {
    if (this.store.data.events[event.id]) return 'duplicate';
    this.store.data.events[event.id] = Date.now();
    const result = this.applyPaymentEvent(event);
    this.store.save();
    return result;
  }

  applyPaymentEvent(event) {
    const intent = event.data?.object;
    if (!event.type?.startsWith('payment_intent.') || !intent) return 'ignored';
    const order = this.store.data.orders[intent.metadata?.order_id];
    if (!order || order.paymentIntentId !== intent.id) return 'stale';
    switch (event.type) {
      case 'payment_intent.succeeded':
        if (intent.amount !== order.quote.totalCents || intent.currency !== order.quote.currency) {
          order.status = 'needs_review'; // Do not mark the order successful if the amount differs from the server quote.
          return 'amount_mismatch';
        }
        order.status = 'paid';
        order.failure = null;
        order.paidAt = Date.now();
        return 'paid';
      case 'payment_intent.payment_failed':
        if (order.status === 'paid') return 'ignored';
        order.status = 'payment_failed';
        order.failure = {
          code: intent.last_payment_error?.code ?? null,
          declineCode: intent.last_payment_error?.decline_code ?? null,
          message: intent.last_payment_error?.message ?? 'Your payment was declined.',
        };
        return 'payment_failed';
      case 'payment_intent.canceled':
        if (order.status === 'paid') return 'ignored';
        order.status = 'canceled';
        return 'canceled';
      default:
        return 'ignored';
    }
  }
}

function validateAddress(address) {
  if (!address || ADDRESS_FIELDS.some((f) => typeof address[f] !== 'string' || !address[f].trim())) {
    throw new QuoteError('profile_incomplete', `Delivery address needs: ${ADDRESS_FIELDS.join(', ')}.`, 422);
  }
  return Object.fromEntries(['name', ...ADDRESS_FIELDS, 'line2'].filter((f) => address[f]).map((f) => [f, address[f].trim()]));
}

export { quoteHash };
