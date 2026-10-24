#!/bin/zsh
# Tuck AI(가구 추천)를 터미널에서 테스트한다. 사용: scripts/test-ai.sh ["질문"]
set -e
cd "${0:A:h}/.."
out=$(mktemp -d)
swiftc -o "$out/ai-test" scripts/ai-test/main.swift Tuck/Services/{ClaudeClient,Secrets,ProductCatalog}.swift
"$out/ai-test" "data/TUCK_Product_Catalog - 시트1.csv" "$@"
