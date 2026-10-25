/** Test pricing policy. The server calculates all amounts from the catalog and this table only. */
export const DEFAULT_SHIPPING_CENTS = 2999; // Flat shipping rate when the catalog has no shipping fee.
export const DEFAULT_TAX_RATE = 0.07;
const TAX_RATE_BY_STATE = { CA: 0.0875, NY: 0.08875, WA: 0.101, TX: 0.0825, OR: 0, MT: 0, NH: 0, DE: 0 };
export const MAX_QUANTITY = 5;

export function shippingCents(product) {
  return product.shippingFeeCents ?? DEFAULT_SHIPPING_CENTS;
}

/** Only the product amount is taxable. Round to the nearest cent. */
export function taxCents(subtotalCents, state) {
  const rate = TAX_RATE_BY_STATE[String(state ?? '').toUpperCase()] ?? DEFAULT_TAX_RATE;
  return Math.round(subtotalCents * rate);
}

export function price(product, quantity, address) {
  const subtotalCents = product.priceCents * quantity;
  const shipping = shippingCents(product);
  const tax = taxCents(subtotalCents, address?.state);
  return { unitCents: product.priceCents, subtotalCents, shippingCents: shipping, taxCents: tax, totalCents: subtotalCents + shipping + tax };
}
