#!/bin/zsh
# `.env`에서 앱이 쓰는 Tuck/Services/Secrets.swift 를 만든다. (비밀 서버 키는 앱에 넣지 않는다.)
set -e
cd "${0:A:h}/.."
set -a; source .env; set +a
: ${ANTHROPIC_API_KEY:?} ${STRIPE_PUBLISHABLE_KEY:?}
cat > Tuck/Services/Secrets.swift <<EOF
import Foundation

// scripts/gen-secrets.sh 가 .env 에서 생성한다. 직접 수정하지 않는다. (gitignore 대상)
enum Secrets {
    static let anthropicAPIKey = "$ANTHROPIC_API_KEY"
    static let backendURL = URL(string: "${BACKEND_URL:-http://localhost:8787}")!
    static let stripePublishableKey = "$STRIPE_PUBLISHABLE_KEY"
}
EOF
