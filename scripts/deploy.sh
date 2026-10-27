#!/usr/bin/env bash
# Build the service (v3), push it to the local registry, deploy it from the registry by digest and call it.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "${ROOT}"

say "Build svc:v3 (multi-stage, distroless, non-root, bases pinned by digest) with the token as a build secret"
docker build --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v3 --build-arg "COMMIT=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" --tag "${REGISTRY}/svc:v3" .

say "Push it to the local registry"
digest="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
echo "pushed ${REGISTRY}/svc:v3 as ${digest}"

say "Deploy by digest: the name below cannot change meaning, even if the tag v3 is moved"
export SVC_IMAGE="${REGISTRY}/svc@${digest}"
docker compose --profile deploy up --detach --wait svc
port="${SVC_PORT:-8089}"
echo "GET /health  -> $(curl -fsS "http://127.0.0.1:${port}/health")"
echo "GET /version -> $(curl -fsS "http://127.0.0.1:${port}/version")"
echo "user         -> $(docker inspect --format '{{.Config.User}}' "$(docker compose --profile deploy ps -q svc)")"
echo "health       -> $(docker inspect --format '{{.State.Health.Status}}' "$(docker compose --profile deploy ps -q svc)")"
