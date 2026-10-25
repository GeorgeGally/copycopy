#!/bin/bash
set -euo pipefail

ROGER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
ROGER_COMPILER="$(xcrun --find swiftc)"
ROGER_HEADERS="$(dirname "$(dirname "$ROGER_COMPILER")")/include/swift"
ROGER_FLAGS=()

# Some CLT upgrades leave the old map beside its replacement. Hide only that
# duplicate in this build; never alter the machine's installed toolchain.
if [[ -f "$ROGER_HEADERS/module.modulemap" && -f "$ROGER_HEADERS/bridging.modulemap" ]] \
    && grep -q '^module SwiftBridging' "$ROGER_HEADERS/module.modulemap" \
    && grep -q '^module SwiftBridging' "$ROGER_HEADERS/bridging.modulemap"; then
    mkdir -p "$ROGER_ROOT/.build"
    ROGER_EMPTY="$ROGER_ROOT/.build/roger-empty.modulemap"
    ROGER_OVERLAY="$ROGER_ROOT/.build/roger-toolchain.json"
    : > "$ROGER_EMPTY"
    json_string() {
        local value="${1//\\/\\\\}"
        value="${value//\"/\\\"}"
        printf '"%s"' "$value"
    }
    {
        printf '{"version":0,"roots":[{"type":"file","name":'
        json_string "$ROGER_HEADERS/module.modulemap"
        printf ',"external-contents":'
        json_string "$ROGER_EMPTY"
        printf '}]}'
    } > "$ROGER_OVERLAY"
    ROGER_FLAGS=(-Xswiftc -vfsoverlay -Xswiftc "$ROGER_OVERLAY")
fi

exec swift "$@" --package-path "$ROGER_ROOT" ${ROGER_FLAGS[@]+"${ROGER_FLAGS[@]}"}
