import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

/** 저장소 루트의 `.env`(KEY=VALUE)를 읽는다. 이미 설정된 환경변수는 덮어쓰지 않는다. */
export function loadDotEnv(file = path.join(root, '.env'), env = process.env) {
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && match[2] && !env[match[1]]) env[match[1]] = match[2];
  }
}

/** 환경변수에서 설정을 읽는다. 비밀 키는 이 서버의 환경변수에만 존재한다. */
export function loadConfig(env = process.env) {
  const stripeSecretKey = env.STRIPE_SECRET_KEY ?? '';
  // 테스트 모드 전용 서버: 라이브 키로는 시작하지 않는다.
  if (!stripeSecretKey.startsWith('sk_test_')) {
    throw new Error('STRIPE_SECRET_KEY must be a Stripe TEST key (sk_test_...).');
  }
  const webhookSecret = env.STRIPE_WEBHOOK_SECRET ?? '';
  if (!webhookSecret.startsWith('whsec_')) {
    throw new Error('STRIPE_WEBHOOK_SECRET (whsec_...) is required to verify webhooks.');
  }
  return {
    port: Number(env.PORT ?? 8787),
    stripeSecretKey,
    webhookSecret,
    stripeApiBase: env.STRIPE_API_BASE ?? 'https://api.stripe.com',
    quoteSecret: env.QUOTE_SECRET ?? stripeSecretKey,
    catalogPath: env.CATALOG_PATH ?? path.join(root, 'data', 'TUCK_Product_Catalog - 시트1.csv'),
    dataFile: env.DATA_FILE ?? path.join(root, 'backend', '.data', 'store.json'),
    maxOrderCents: Number(env.MAX_ORDER_CENTS ?? 500_000),
    // 프로필 화면이 완성되기 전까지, 기기 등록 시 테스트 카드(pm_card_visa)를 고객에 붙여 둔다.
    seedTestPaymentMethod: (env.SEED_TEST_PAYMENT_METHOD ?? 'true') === 'true',
  };
}
