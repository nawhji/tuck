#!/bin/zsh
# Test the app purchase flow (CheckoutClient, models, ReplyParser) against the backend development server (mock Stripe).
# Usage: scripts/test-checkout.sh
set -e
cd "${0:A:h}/.."
out=$(mktemp -d)
swiftc -o "$out/checkout-test" scripts/checkout-test/main.swift \
  Tuck/Services/{CheckoutClient,Secrets,ProductCatalog}.swift Tuck/Models/{ChatMessage,Checkout}.swift
node backend/test/dev-server.js > "$out/server.json" 2> "$out/server.log" &
server=$!
until [[ -s "$out/server.json" ]]; do sleep 0.2; done
rc=0
"$out/checkout-test" $(node -e 'const s=require(process.argv[1]);console.log(s.base,s.control)' "$out/server.json") || rc=$?
kill $server 2>/dev/null
exit $rc
