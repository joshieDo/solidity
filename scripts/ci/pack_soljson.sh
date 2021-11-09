#!/bin/bash

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SOLJSON_JS="$1"
SOLJSON_WASM="$2"
SOLJSON_WASM_SIZE=$(wc -c "${SOLJSON_WASM}" | cut -d ' ' -f 1)
OUTPUT="$3"

{
  echo -n "\"use strict\";"
  echo -n "var Module = Module || {}; Module[\"wasmBinary\"] = "
  cat "${SCRIPT_DIR}/wasm_unpack.js"
  echo -n "(\""
  lz4c --no-frame-crc --best --favor-decSpeed "${SOLJSON_WASM}" - | base64 -w 0 | sed 's/[^A-Za-z0-9\+\/]//g'
  echo -n "\",${SOLJSON_WASM_SIZE});"
  sed -e 's/"use strict";//' "${SOLJSON_JS}"
} > "${OUTPUT}"
