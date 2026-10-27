#!/usr/bin/env bash
# Done when (step 1): docker history --no-trunc on the one-stage image shows the token.
# Done when (step 3): docker history no longer shows the token anywhere, and the image has no .netrc.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc
CLEANUP_IMAGES+=(svc:v0 svc:v2 svc:v3)

say "v0: the token passed as a build argument"
build_version v0 "${ROOT}" > /dev/null 2>&1
docker history --no-trunc svc:v0 | grep 'demo-token-123' | cut -c1-200 | sed -n '1,2p'
check "the token is readable in the v0 history" "$([ "$(docker history --no-trunc svc:v0 | grep -c 'demo-token-123')" -ge 1 ] && echo yes || echo no)" yes

say "v2 and v3: the token passed as a build secret"
build_version v2 "${ROOT}" > /dev/null 2>&1
build_version v3 "${ROOT}" > /dev/null 2>&1
for version in v2 v3; do
  check "no token anywhere in the ${version} history" "$(docker history --no-trunc "svc:${version}" | grep -c 'demo-token-123' || true)" 0
  docker create --name "svc-export-${version}" "svc:${version}" > /dev/null
  netrc_entries="$(docker export "svc-export-${version}" | tar -t 2> /dev/null | grep -c 'netrc' || true)"
  docker rm -f "svc-export-${version}" > /dev/null
  check "no .netrc file in the ${version} image" "${netrc_entries}" 0
done
finish
