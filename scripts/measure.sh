#!/usr/bin/env bash
# Build v0 to v4 and measure each: image size, cold build, warm build after a one-line change, critical and high
# vulnerabilities, and whether the token is in the image history. Writes docs/measurements.md.
# Cold means: no layer cache and empty cache mounts on the project's own builder (base images already pulled).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc

WORK="$(mktemp -d)"
CLEANUP_DIRS+=("${WORK}")
tar --exclude=.git --exclude=docs -cf - . | tar -xf - -C "${WORK}"

# Empty the builder's cache mounts so a cold build downloads modules and recompiles the standard library.
forget_cache_mounts() {
  docker buildx prune --builder "${BUILDER}" --force --filter type=exec.cachemount > /dev/null 2>&1 \
    || docker buildx prune --builder "${BUILDER}" --force > /dev/null
}
touch_source() { printf '\n// one-line change for the warm build: %s at %s\n' "$1" "$(date +%s)" >> "${WORK}/cmd/svc/main.go"; }

what_changed() {
  case "$1" in
    v0) echo "one stage on the full SDK image, token as a build argument" ;;
    v1) echo "multi-stage, debian slim runtime" ;;
    v2) echo "secret mount for the token, cache mounts" ;;
    v3) echo "distroless static, non-root, bases pinned by digest" ;;
    v4) echo "v3 plus SBOM and provenance" ;;
  esac
}

ROWS=""
for version in v0 v1 v2 v3; do
  say "${version}"
  forget_cache_mounts
  cold="$(seconds_of build_version "${version}" "${WORK}" --no-cache)"
  touch_source "${version}"
  warm="$(seconds_of build_version "${version}" "${WORK}")"
  size="$(megabytes "$(image_bytes "svc:${version}")")"
  vulnerabilities="$(high_critical "svc:${version}")"
  leaked="$(docker history --no-trunc "svc:${version}" | grep -c 'demo-token-123' || true)"
  echo "size ${size} MB, cold ${cold} s, warm ${warm} s, critical/high ${vulnerabilities}, token lines in history ${leaked}"
  ROWS+="| ${version} | $(what_changed "${version}") | ${size} MB | ${cold} s | ${warm} s | ${vulnerabilities} | ${leaked} |"$'\n'
done

say "v4: the v3 Dockerfile built with an SBOM and provenance, pushed to ${REGISTRY}"
v4_build() {
  docker buildx build --builder "${BUILDER}" --sbom=true --provenance=mode=max --push \
    --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v4 --tag "${REGISTRY}/svc:v4" "$@" "${WORK}"
}
forget_cache_mounts
cold="$(seconds_of v4_build --no-cache)"
touch_source v4
warm="$(seconds_of v4_build)"
docker pull --quiet "${REGISTRY}/svc:v4" > /dev/null
size="$(megabytes "$(image_bytes "${REGISTRY}/svc:v4")")"
vulnerabilities="$(high_critical "${REGISTRY}/svc:v4")"
leaked="$(docker history --no-trunc "${REGISTRY}/svc:v4" | grep -c 'demo-token-123' || true)"
echo "size ${size} MB, cold ${cold} s, warm ${warm} s, critical/high ${vulnerabilities}, token lines in history ${leaked}"
ROWS+="| v4 | $(what_changed v4) | ${size} MB | ${cold} s | ${warm} s | ${vulnerabilities} | ${leaked} |"$'\n'

{
  echo "# Measurements"
  echo
  echo "Captured by \`make measure\` on $(date -u +%Y-%m-%d) ($(uname -m), Docker $(docker version --format '{{.Server.Version}}'), buildx $(docker buildx version | awk '{print $2}'), scanner ${TRIVY_IMAGE}). Times are wall-clock seconds on one laptop and differ on yours; the order of the rows and the ratios are what matter. Cold: no layer cache and empty cache mounts on the project's own builder, base images already pulled. Warm: one line of \`cmd/svc/main.go\` changed, then a rebuild."
  echo
  echo "| Version | What changed | Image size | Cold build | Warm build (1-line change) | Scanner: critical/high | Token lines in \`docker history\` |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
  printf '%s' "${ROWS}"
} > docs/measurements.md
echo "wrote docs/measurements.md"
