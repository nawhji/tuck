import crypto from 'node:crypto';
import { buildQuote, QuoteError, quoteHash } from './quote.js';
import { StripeError } from './stripe.js';

const REUSABLE_PI = new Set(['requires_payment_method', 'requires_confirmation', 'requires_action', 'processing']);
const ADDRESS_FIELDS = ['line1', 'city', 'state', 'postalCode', 'country'];
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

/** 주문·결제 로직. 금액·재고·소유권 판단은 모두 여기서 서버 데이터로만 한다. */
export class Orders {
  constructor({ config, store, catalog, stripe }) {
    Object.assign(this, { config, store, catalog, stripe });
    this.locks = new Map();
  }

  /** 같은 주문에 대한 요청을 한 번에 하나씩 처리한다. (더블 탭·재시도 경합 방지) */
  async withLock(orderId, work) {
    const previous = this.locks.get(orderId) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(work);
    const tail = run.catch(() => {});
    this.locks.set(orderId, tail);
    try { return await run; } finally { if (this.locks.get(orderId) === tail) this.locks.delete(orderId); }
  }

  // MARK: Devices

  /** 로그인이 없으므로 기기마다 익명 토큰과 Stripe Customer를 만든다. 프로필(주소)은 이후 프로필 화면이 채운다. */
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

  /** 소유자가 아니면 존재 여부도 알리지 않는다. */
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

    // 지금 시점의 신뢰 데이터로 견적을 다시 계산한다. 달라졌거나 사용자가 본 견적과 다르면 다시 확인받는다.
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

  /** 견적이 바뀌면 이전 PaymentIntent는 버리고 주문을 다시 확인 대기로 되돌린다. */
  async replaceQuote(order, quote) {
    const stale = order.paymentIntentId;
    order.paymentIntentId = null;
    order.quote = quote;
    order.status = 'quoted';
    order.failure = null;
    this.store.save();
    if (stale) await this.stripe.cancelPaymentIntent(stale).catch(() => {});
  }

  /** 주문당 시도 횟수를 멱등 키에 넣어, 같은 시도는 몇 번을 요청해도 PaymentIntent가 하나만 생기게 한다. */
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
          // 이미 결제가 끝났으면 취소할 수 없다. 웹훅이 최종 상태를 정한다.
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

  /** 웹훅이 아직 안 왔거나(로컬 개발 등) 유실돼도 진행되도록, 결제 대기 중인 주문은 Stripe에서 직접 조회한 상태로 확정한다. */
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

  /** 서명이 검증된 이벤트만 들어온다. 같은 이벤트·오래된 PaymentIntent·순서가 뒤바뀐 이벤트는 상태를 망가뜨리지 않는다. */
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
          order.status = 'needs_review'; // 금액이 서버 견적과 다르면 성공으로 처리하지 않는다.
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
