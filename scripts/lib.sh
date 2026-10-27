#!/usr/bin/env bash
# Shared helpers. Source this file; it is not run on its own.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUILDER="${BUILDER:-shrink-and-harden}"
export TRIVY_IMAGE="aquasec/trivy:0.58.0"
FAILED=0
CLEANUP_CONTAINERS=()
CLEANUP_IMAGES=()
CLEANUP_DIRS=()

if [ -f "${ROOT}/.env" ]; then
  # shellcheck disable=SC1091
  . "${ROOT}/.env"
fi
export REGISTRY="localhost:${REGISTRY_PORT:-5057}"

say() { printf '\n== %s\n' "$*"; }

# check <description> <actual> <expected>: print PASS or FAIL and remember a failure for the exit code.
check() {
  if [ "$2" = "$3" ]; then
    printf 'PASS %s (%s)\n' "$1" "$2"
  else
    printf 'FAIL %s: got %s, expected %s\n' "$1" "$2" "$3"
    FAILED=1
  fi
}

# check_true <description> <awk condition on a and b> <a> <b>: numeric comparison such as "a < b".
check_true() {
  if awk -v a="$3" -v b="$4" "BEGIN { exit !(${2}) }"; then
    printf 'PASS %s (%s, %s)\n' "$1" "$3" "$4"
  else
    printf 'FAIL %s: %s, %s do not satisfy %s\n' "$1" "$3" "$4" "$2"
    FAILED=1
  fi
}

cleanup() {
  local item
  for item in ${CLEANUP_CONTAINERS[@]+"${CLEANUP_CONTAINERS[@]}"}; do docker rm -f "${item}" > /dev/null 2>&1 || true; done
  for item in ${CLEANUP_IMAGES[@]+"${CLEANUP_IMAGES[@]}"}; do docker rmi -f "${item}" > /dev/null 2>&1 || true; done
  for item in ${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}; do rm -rf "${item}"; done
}
trap cleanup EXIT

seconds_of() { # seconds_of <command...>: run quietly, print elapsed wall-clock seconds with two decimals
  local start end
  start="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  "$@" > /dev/null 2>&1
  end="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  awk -v s="${start}" -v e="${end}" 'BEGIN { printf "%.2f", e - s }'
}

image_bytes() { docker image inspect --format '{{.Size}}' "$1"; }
megabytes() { awk -v bytes="$1" 'BEGIN { printf "%.0f", bytes / 1000000 }'; }

# build <version> <dockerfile> <context> [extra buildx args]: build and load an image svc:<version> on the project's builder.
build() {
  local version="$1" dockerfile="$2" context="$3"
  shift 3
  docker buildx build --builder "${BUILDER}" --load --file "${dockerfile}" --tag "svc:${version}" "$@" "${context}"
}
# Arguments by version: v0 takes the token as a build argument (the mistake), v1 does not use it, v2 and later take it
# as a secret.
args_for() {
  case "$1" in
    v0) printf '%s\n' --build-arg "PKG_TOKEN=${PKG_TOKEN:-demo-token-123}" ;;
    v1) ;;
    *) printf '%s\n' --secret "id=netrc,src=${ROOT}/netrc" ;;
  esac
}
dockerfile_for() {
  case "$1" in
    v0 | v1 | v2) echo "${ROOT}/build/history/$1.Dockerfile" ;;
    *) echo "${ROOT}/Dockerfile" ;;
  esac
}
build_version() { # build_version <version> <context> [extra args]: the right Dockerfile and secret arguments for a version
  local version="$1" context="$2" extra=()
  shift 2
  while IFS= read -r line; do extra+=("${line}"); done < <(args_for "${version}")
  build "${version}" "$(dockerfile_for "${version}")" "${context}" "${extra[@]}" "$@"
}

# high_critical <image>: the scanner's count of critical and high vulnerabilities as "critical/high".
high_critical() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v shrink-trivy-cache:/root/.cache/ "${TRIVY_IMAGE}" \
    image --quiet --scanners vuln --format json "$1" 2> /dev/null \
    | jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | "\(map(select(. == "CRITICAL")) | length)/\(map(select(. == "HIGH")) | length)"'
}

# serve_and_get <image> <port> <path>: run the image, fetch a path, remove the container.
serve_and_get() {
  local name="svc-smoke-$$"
  CLEANUP_CONTAINERS+=("${name}")
  docker run -d --name "${name}" -p "127.0.0.1:$2:8080" "$1" > /dev/null
  local body=""
  for _ in $(seq 1 40); do
    body="$(curl -fsS "http://127.0.0.1:$2$3" 2> /dev/null)" && break
    sleep 0.25
  done
  docker rm -f "${name}" > /dev/null
  printf '%s' "${body}"
}

finish() {
  if [ "${FAILED}" -eq 0 ]; then printf '\nOK\n'; else printf '\nFAILED\n'; fi
  exit "${FAILED}"
}
