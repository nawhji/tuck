#!/bin/zsh
# Test Tuck's furniture recommendation AI from the terminal. Usage: scripts/test-ai.sh ["question"]
set -e
cd "${0:A:h}/.."
out=$(mktemp -d)
swiftc -o "$out/ai-test" scripts/ai-test/main.swift Tuck/Services/{ClaudeClient,Secrets,ProductCatalog}.swift Tuck/Models/{ChatMessage,Checkout}.swift
"$out/ai-test" "data/TUCK_Product_Catalog.csv" "$@"
