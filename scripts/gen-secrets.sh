#!/bin/zsh
# Creates Tuck/Services/Secrets.swift from `.env`. Never put server secret keys in the app.
set -e
cd "${0:A:h}/.."
set -a; source .env; set +a
: ${ANTHROPIC_API_KEY:?} ${STRIPE_PUBLISHABLE_KEY:?}
cat > Tuck/Services/Secrets.swift <<EOF
import Foundation

// Generated from .env by scripts/gen-secrets.sh. Do not edit directly. (Ignored by git.)
enum Secrets {
    static let anthropicAPIKey = "$ANTHROPIC_API_KEY"
    static let backendURL = URL(string: "${BACKEND_URL:-http://localhost:8787}")!
    static let stripePublishableKey = "$STRIPE_PUBLISHABLE_KEY"
}
EOF
