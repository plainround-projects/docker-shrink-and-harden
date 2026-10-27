#!/usr/bin/env bash
# Done when (step 6): "does this image contain library X, and which version?" is answered from the SBOM alone.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc

docker buildx build --builder "${BUILDER}" --sbom=true --provenance=mode=max --push \
  --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v4 --tag "${REGISTRY}/svc:v4" . > /dev/null 2>&1
sbom="$(docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .SBOM }}')"
provenance="$(docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .Provenance }}')"

say "the packages the SBOM lists for this binary: the Go standard library and the service module"
echo "${sbom}" | jq -r '.SPDX.packages[] | select(.name == "stdlib" or .name == "example.com/svc") | "\(.name) \(.versionInfo)"'
check "the SBOM lists the Go standard library" "$(echo "${sbom}" | jq -r '[.SPDX.packages[] | select(.name == "stdlib")] | length > 0')" true
check "the SBOM lists the service module" "$(echo "${sbom}" | jq -r '[.SPDX.packages[] | select(.name == "example.com/svc")] | length > 0')" true
check "the SBOM names a Go version for the standard library" "$(echo "${sbom}" | jq -r '[.SPDX.packages[] | select(.name == "stdlib") | .versionInfo | test("^go?[0-9]|^[0-9]")] | any')" true
echo "${provenance}" | jq -r '.SLSA.buildDefinition.buildType'
check "the provenance names the build type" "$(echo "${provenance}" | jq -r '(.SLSA.buildDefinition.buildType // "") != ""')" true
check "the provenance lists the pinned base images it was built from" "$(echo "${provenance}" | jq -r '[.SLSA.buildDefinition.resolvedDependencies[]?.uri | select(test("golang|distroless"))] | length >= 2')" true
finish
