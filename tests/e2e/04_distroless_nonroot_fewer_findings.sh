#!/usr/bin/env bash
# Done when (step 4): the image runs as non-root on a minimal base, and the scanner's count drops.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc
CLEANUP_IMAGES+=(svc:v1 svc:v3)

build_version v1 "${ROOT}" > /dev/null 2>&1
build_version v3 "${ROOT}" > /dev/null 2>&1
check "the image declares a non-root user" "$(docker inspect --format '{{.Config.User}}' svc:v3)" "nonroot:nonroot"
check "the smoke test still passes: GET /health" "$(serve_and_get svc:v3 18082 /health)" "ok"
check "there is no shell to exec into" "$(docker run --rm --entrypoint sh svc:v3 -c true > /dev/null 2>&1 && echo shell || echo none)" none
count_v1="$(high_critical svc:v1)"
count_v3="$(high_critical svc:v3)"
say "scanner critical/high: v1 ${count_v1}, v3 ${count_v3}"
check_true "the v3 count is not above the v1 count" "a <= b" "$(( ${count_v3%%/*} + ${count_v3##*/} ))" "$(( ${count_v1%%/*} + ${count_v1##*/} ))"
finish
