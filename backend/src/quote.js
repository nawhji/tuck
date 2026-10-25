import crypto from 'node:crypto';
import { price, MAX_QUANTITY } from './pricing.js';

const MAX_ALTERNATIVES = 3;
const FOOTPRINT_TOLERANCE = 1.15; // 대체 상품은 원래 놓인 자리(가로·세로)의 115% 안에 들어와야 한다.

export class QuoteError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/** 견적 서명: 결제 금액과 견적 내용이 바뀌면 값이 달라진다. 클라이언트가 승인한 견적과 비교하는 데 쓴다. */
export function quoteHash(secret, ownerId, quote) {
  const canonical = JSON.stringify([
    ownerId, quote.product.id, quote.quantity, quote.unitCents, quote.shippingCents, quote.taxCents,
    quote.totalCents, quote.currency, quote.address,
  ]);
  return crypto.createHmac('sha256', secret).update(canonical).digest('hex').slice(0, 32);
}

const publicProduct = (p) => ({ id: p.id, name: p.name, brand: p.brand, imageUrl: p.imageUrl, category: p.category });
const isAvailable = (p) => p.availability === 'in_stock' && p.priceCents != null;

export function validateQuantity(quantity) {
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) {
    throw new QuoteError('invalid_quantity', `Quantity must be between 1 and ${MAX_QUANTITY}.`);
  }
}

/** 상품·수량·배송지로 견적을 만든다. 가격은 전부 카탈로그에서 계산한다. */
export function buildQuote({ catalog, secret, ownerId, productId, quantity, address, budgetCents }) {
  validateQuantity(quantity);
  if (budgetCents != null && (!Number.isInteger(budgetCents) || budgetCents <= 0)) {
    throw new QuoteError('invalid_budget', 'Budget must be a positive number of cents.');
  }
  const product = catalog.get(productId);
  if (!product) throw new QuoteError('unknown_product', 'That product is not in the catalog.', 404);
  const base = {
    product: publicProduct(product),
    quantity,
    currency: product.currency,
    address,
    budgetCents: budgetCents ?? null,
    test: true,
  };
  if (!isAvailable(product)) {
    return { status: 'unavailable', quote: base, alternatives: alternatives({ catalog, product, quantity, address, budgetCents }) };
  }
  const quote = { ...base, ...price(product, quantity, address) };
  quote.hash = quoteHash(secret, ownerId, quote);
  if (budgetCents != null && quote.totalCents > budgetCents) {
    return { status: 'over_budget', quote, alternatives: alternatives({ catalog, product, quantity, address, budgetCents }) };
  }
  return { status: 'ok', quote, alternatives: [] };
}

const overlap = (a, b) => a.filter((x) => b.includes(x)).length;

/**
 * 예산 안에서 같은 종류의 대체 상품을 찾는다. 배치(자리 크기)와 스타일을 지키기 위해
 * 원래 상품의 가로·세로 안에 들어오는 상품을 먼저, 스타일 태그·색상이 겹치는 상품을 먼저 보여준다.
 */
export function alternatives({ catalog, product, quantity, address, budgetCents }) {
  const fits = (p) => (
    product.widthIn == null || p.widthIn == null || (p.widthIn <= product.widthIn * FOOTPRINT_TOLERANCE
    && p.depthIn <= product.depthIn * FOOTPRINT_TOLERANCE)
  );
  return catalog.products
    .filter((p) => p.id !== product.id && p.category === product.category && isAvailable(p))
    .map((p) => {
      const quote = { ...price(p, quantity, address), product: publicProduct(p), quantity, currency: p.currency, address };
      return { p, quote, fitsPlacement: fits(p), styleMatch: overlap(p.styleTags, product.styleTags) + (p.colorFamily === product.colorFamily ? 1 : 0) };
    })
    .filter(({ quote }) => budgetCents == null || quote.totalCents <= budgetCents)
    .sort((a, b) => (b.fitsPlacement - a.fitsPlacement) || (b.styleMatch - a.styleMatch) || (b.quote.totalCents - a.quote.totalCents))
    .slice(0, MAX_ALTERNATIVES)
    .map(({ p, quote, fitsPlacement, styleMatch }) => ({
      product: publicProduct(p), totalCents: quote.totalCents, fitsPlacement, styleMatch, styleTags: p.styleTags, colorFamily: p.colorFamily,
    }));
}
