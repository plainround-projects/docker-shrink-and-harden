#!/usr/bin/env bash
# The domain and application packages must keep at least 95 percent statement coverage.
set -euo pipefail

GO_IMAGE="${GO_IMAGE:?run through make test, which sets GO_IMAGE}"
status=0
for package in domain application; do
  output="$(docker run --rm -v "$(pwd)":/src -v shrink-gomod:/go/pkg/mod -v shrink-gobuild:/root/.cache/go-build -w /src "${GO_IMAGE}" go test -cover "./internal/${package}/...")"
  percent="$(echo "${output}" | sed -n 's/.*coverage: \([0-9.]*\)%.*/\1/p')"
  if awk -v p="${percent}" 'BEGIN { exit !(p >= 95) }'; then
    echo "coverage of internal/${package}: ${percent}% (needs 95%)"
  else
    echo "coverage of internal/${package}: ${percent:-none}% is below 95%"
    status=1
  fi
done
exit "${status}"
