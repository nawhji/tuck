#!/bin/zsh
# 앱의 구매 흐름 코드(CheckoutClient·모델·ReplyParser)를 backend 개발 서버(가짜 Stripe)에 붙여 검증한다.
# 사용: scripts/test-checkout.sh
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
