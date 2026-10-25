/** 테스트용 가격 정책. 모든 금액은 서버가 카탈로그와 이 표로만 계산한다. */
export const DEFAULT_SHIPPING_CENTS = 2999; // 카탈로그에 배송비가 없을 때의 정액 배송비
export const DEFAULT_TAX_RATE = 0.07;
const TAX_RATE_BY_STATE = { CA: 0.0875, NY: 0.08875, WA: 0.101, TX: 0.0825, OR: 0, MT: 0, NH: 0, DE: 0 };
export const MAX_QUANTITY = 5;

export function shippingCents(product) {
  return product.shippingFeeCents ?? DEFAULT_SHIPPING_CENTS;
}

/** 과세 대상은 상품 금액이다. 센트 단위로 반올림한다. */
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
