#!/usr/bin/env bash
# Done when (step 2): the image is under a quarter of its original size and still passes the smoke test.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc
CLEANUP_IMAGES+=(svc:v0 svc:v1)

build_version v0 "${ROOT}" > /dev/null 2>&1
build_version v1 "${ROOT}" > /dev/null 2>&1
v0="$(image_bytes svc:v0)"
v1="$(image_bytes svc:v1)"
say "sizes: v0 $(megabytes "${v0}") MB, v1 $(megabytes "${v1}") MB"
check_true "v1 is under a quarter of v0" "a < b / 4" "${v1}" "${v0}"
check "the v1 smoke test: GET /health" "$(serve_and_get svc:v1 18081 /health)" "ok"
finish
