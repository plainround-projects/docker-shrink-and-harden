#!/usr/bin/env bash
# Build v4: the same Dockerfile as v3, built with an SBOM and provenance attestation and pushed to the local registry.
# Then answer "which packages are inside, and was it built from this commit?" from the registry alone.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "${ROOT}"

say "Build and push svc:v4 with --sbom=true --provenance=mode=max (needs the docker-container builder)"
docker buildx build --builder "${BUILDER}" --sbom=true --provenance=mode=max --push \
  --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v4 --build-arg "COMMIT=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" --tag "${REGISTRY}/svc:v4" .

say "Packages in the SBOM"
docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .SBOM }}' | jq -r '.SPDX.packages[] | select(.versionInfo != null) | "\(.name) \(.versionInfo)"' | sort

say "Does the image contain the Go standard library, and which version?"
docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .SBOM }}' | jq -r '.SPDX.packages[] | select(.name == "stdlib") | "\(.name) \(.versionInfo)"'

say "Provenance: what built this image, and from which pinned inputs"
provenance="$(docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .Provenance }}')"
echo "${provenance}" | jq -r '"build type: \(.SLSA.buildDefinition.buildType)"'
echo "${provenance}" | jq -r '.SLSA.buildDefinition.resolvedDependencies[]? | "input: \(.uri) \(.digest | to_entries[0] | "\(.key):\(.value[0:19])...")"'
