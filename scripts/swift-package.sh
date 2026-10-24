#!/bin/bash
set -euo pipefail

COPYCOPY_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
COPYCOPY_COMPILER="$(xcrun --find swiftc)"
COPYCOPY_HEADERS="$(dirname "$(dirname "$COPYCOPY_COMPILER")")/include/swift"
COPYCOPY_FLAGS=()

# Some CLT upgrades leave the old map beside its replacement. Hide only that
# duplicate in this build; never alter the machine's installed toolchain.
if [[ -f "$COPYCOPY_HEADERS/module.modulemap" && -f "$COPYCOPY_HEADERS/bridging.modulemap" ]] \
    && grep -q '^module SwiftBridging' "$COPYCOPY_HEADERS/module.modulemap" \
    && grep -q '^module SwiftBridging' "$COPYCOPY_HEADERS/bridging.modulemap"; then
    mkdir -p "$COPYCOPY_ROOT/.build"
    COPYCOPY_EMPTY="$COPYCOPY_ROOT/.build/copycopy-empty.modulemap"
    COPYCOPY_OVERLAY="$COPYCOPY_ROOT/.build/copycopy-toolchain.json"
    : > "$COPYCOPY_EMPTY"
    json_string() {
        local value="${1//\\/\\\\}"
        value="${value//\"/\\\"}"
        printf '"%s"' "$value"
    }
    {
        printf '{"version":0,"roots":[{"type":"file","name":'
        json_string "$COPYCOPY_HEADERS/module.modulemap"
        printf ',"external-contents":'
        json_string "$COPYCOPY_EMPTY"
        printf '}]}'
    } > "$COPYCOPY_OVERLAY"
    COPYCOPY_FLAGS=(-Xswiftc -vfsoverlay -Xswiftc "$COPYCOPY_OVERLAY")
fi

exec swift "$@" --package-path "$COPYCOPY_ROOT" "${COPYCOPY_FLAGS[@]}"
