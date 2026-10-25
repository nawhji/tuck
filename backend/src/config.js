import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

/** Reads `.env` (KEY=VALUE) from the repository root without overriding existing environment variables. */
export function loadDotEnv(file = path.join(root, '.env'), env = process.env) {
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && match[2] && !env[match[1]]) env[match[1]] = match[2];
  }
}

/** Reads configuration from environment variables. Secret keys exist only in this server's environment. */
export function loadConfig(env = process.env) {
  const stripeSecretKey = env.STRIPE_SECRET_KEY ?? '';
  // Test-mode server only: refuse to start with live keys.
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
    catalogPath: env.CATALOG_PATH ?? path.join(root, 'data', 'TUCK_Product_Catalog.csv'),
    dataFile: env.DATA_FILE ?? path.join(root, 'backend', '.data', 'store.json'),
    maxOrderCents: Number(env.MAX_ORDER_CENTS ?? 500_000),
    // Until the profile screen is complete, attach a test card (pm_card_visa) to the customer at device registration.
    seedTestPaymentMethod: (env.SEED_TEST_PAYMENT_METHOD ?? 'true') === 'true',
  };
}
