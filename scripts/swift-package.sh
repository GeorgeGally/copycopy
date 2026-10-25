#!/bin/bash
set -euo pipefail

COPYOVER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
COPYOVER_COMPILER="$(xcrun --find swiftc)"
COPYOVER_HEADERS="$(dirname "$(dirname "$COPYOVER_COMPILER")")/include/swift"
COPYOVER_FLAGS=()

# Some CLT upgrades leave the old map beside its replacement. Hide only that
# duplicate in this build; never alter the machine's installed toolchain.
if [[ -f "$COPYOVER_HEADERS/module.modulemap" && -f "$COPYOVER_HEADERS/bridging.modulemap" ]] \
    && grep -q '^module SwiftBridging' "$COPYOVER_HEADERS/module.modulemap" \
    && grep -q '^module SwiftBridging' "$COPYOVER_HEADERS/bridging.modulemap"; then
    mkdir -p "$COPYOVER_ROOT/.build"
    COPYOVER_EMPTY="$COPYOVER_ROOT/.build/copyover-empty.modulemap"
    COPYOVER_OVERLAY="$COPYOVER_ROOT/.build/copyover-toolchain.json"
    : > "$COPYOVER_EMPTY"
    json_string() {
        local value="${1//\\/\\\\}"
        value="${value//\"/\\\"}"
        printf '"%s"' "$value"
    }
    {
        printf '{"version":0,"roots":[{"type":"file","name":'
        json_string "$COPYOVER_HEADERS/module.modulemap"
        printf ',"external-contents":'
        json_string "$COPYOVER_EMPTY"
        printf '}]}'
    } > "$COPYOVER_OVERLAY"
    COPYOVER_FLAGS=(-Xswiftc -vfsoverlay -Xswiftc "$COPYOVER_OVERLAY")
fi

exec swift "$@" --package-path "$COPYOVER_ROOT" ${COPYOVER_FLAGS[@]+"${COPYOVER_FLAGS[@]}"}
