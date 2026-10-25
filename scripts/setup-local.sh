#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep a teammate's existing chat credentials. RoomPlan itself needs no key.
if [ ! -f Tuck/Services/Secrets.swift ]; then
    cat > Tuck/Services/Secrets.swift <<'SWIFT'
// Local only, ignored by git. An empty key is sufficient for RoomPlan.
enum Secrets {
    static let anthropicAPIKey = ""
}
SWIFT
    echo 'Created ignored Secrets.swift with an empty key. Room scanning is ready for a local build.'
else
    echo 'Kept the existing Secrets.swift.'
fi
