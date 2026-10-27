#!/usr/bin/env bash
# Done when (step 5): retagging a tag to a different image does not change what the digest deploy command runs.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc
CLEANUP_IMAGES+=("${REGISTRY}/svc:v3" "${REGISTRY}/svc:other")

say "every FROM in the Dockerfile carries a digest"
froms="$(grep -c '^FROM ' Dockerfile)"
pinned="$(grep -c '^FROM .*@sha256:[0-9a-f]\{64\}' Dockerfile)"
check "pinned FROM lines" "${pinned}" "${froms}"

say "push v3, then move the tag v3 to a different image"
docker build --quiet --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v3 --tag "${REGISTRY}/svc:v3" . > /dev/null
first="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
docker build --quiet --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=other --tag "${REGISTRY}/svc:other" . > /dev/null
docker tag "${REGISTRY}/svc:other" "${REGISTRY}/svc:v3"
second="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
echo "v3 was ${first}; after the move it is ${second}"
check "the tag now points at a different digest" "$([ "${first}" != "${second}" ] && echo different || echo same)" different

say "run by the first digest and by the moved tag"
docker rmi -f "${REGISTRY}/svc:v3" "${REGISTRY}/svc:other" > /dev/null
by_digest="$(serve_and_get "${REGISTRY}/svc@${first}" 18083 /version)"
by_tag="$(serve_and_get "${REGISTRY}/svc:v3" 18084 /version)"
CLEANUP_IMAGES+=("${REGISTRY}/svc@${first}")
echo "by digest: ${by_digest}"
echo "by tag:    ${by_tag}"
check "the digest deploy still runs the first image" "$(echo "${by_digest}" | jq -r .version)" v3
check "the moved tag runs the other image" "$(echo "${by_tag}" | jq -r .version)" other
finish
