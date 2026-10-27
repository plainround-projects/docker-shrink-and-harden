#!/usr/bin/env bash
# Done when (step 3): a warm build after a code change takes a fraction of the original time.
# Seconds depend on the machine, so the check counts the packages `go build -v` compiles: the cache mount holds the
# standard library, so after a one-line change only the service's own packages are compiled again.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc
WORK="$(mktemp -d)"
CLEANUP_DIRS+=("${WORK}")
CLEANUP_IMAGES+=(svc:v2)
tar --exclude=.git --exclude=docs -cf - . | tar -xf - -C "${WORK}"

# compiled_packages <log>: how many packages `go build -v` compiled; packages restored from the cache are not listed.
compiled_packages() {
  local step
  step="$(echo "$1" | grep -m1 'go build' | sed -E 's/^#([0-9]+) .*/\1/')"
  echo "$1" | grep -cE "^#${step} [0-9.]+ [a-z]" || true
}

docker buildx prune --builder "${BUILDER}" --force --filter type=exec.cachemount > /dev/null 2>&1 || true
cold_log="$(build_version v2 "${WORK}" --no-cache --progress=plain 2>&1)"
printf '\n// one-line change at %s\n' "$(date +%s)" >> "${WORK}/cmd/svc/main.go"
warm_log="$(build_version v2 "${WORK}" --progress=plain 2>&1)"
cold="$(compiled_packages "${cold_log}")"
warm="$(compiled_packages "${warm_log}")"
say "packages compiled by go build: cold ${cold}, warm ${warm}"
check_true "a cold build compiles the standard library packages" "a > 50" "${cold}" "${warm}"
check_true "the warm build compiles only the changed package and its dependents" "b < a / 5" "${cold}" "${warm}"

unchanged_log="$(build_version v2 "${WORK}" --progress=plain 2>&1)"
step="$(echo "${unchanged_log}" | grep -m1 'go mod download' | sed -E 's/^#([0-9]+) .*/\1/')"
check "the go mod download step is CACHED on an unchanged rebuild" "$(echo "${unchanged_log}" | grep -c "^#${step} CACHED")" 1
finish
