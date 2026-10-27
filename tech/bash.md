# Bash (shell scripts)

## What it is

A **shell** is a program that reads commands and runs other programs. **Bash** is the most common shell on Linux and the older default on macOS. A **shell script** is a text file of commands; its first line, the **shebang** (`#!/usr/bin/env bash`), says which program should run it. Every script in this repository is Bash.


**Words used in this note**

- **hash**: A short fingerprint computed from the bytes of a file. Change one byte and the fingerprint changes. SHA-256 is a common method; its result is called a digest.
- **layer**: One step of an image build, stored as its own set of file changes. Unchanged layers are reused from the cache.
- **pipe**: The `|` symbol. It connects the output of the command on its left to the input of the command on its right.
- **image**: A read-only bundle of files and settings from which containers are started.
- **registry**: A server that stores and serves images.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **container**: A process (or a group of processes) run in isolation, with its own view of files, network and process list, but sharing the host's kernel.
- **socket**: One end of a network connection. A program reads and writes it like a file.
- **mount**: To make a folder or volume appear at a chosen path inside a container.
- **volume**: Storage managed by Docker that outlives any one container.
- **database**: A program that stores data in an organized way and answers questions about it. PostgreSQL is one.
- **cache**: Saved results that are reused so slow work is not repeated.
- **JSON**: A text format for data. An object is `{"name": "value"}`, a list is `[1, 2]`; values are strings, numbers, `true`, `false` or `null`.
- **process**: A running program. The operating system gives each process a number (its process id, or PID), its own memory and its own list of open files.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **compiler**: A program that turns source code into machine code that the computer can run directly.

## Why this repository uses it

The lesson's work is commands: build, push, run, inspect, time, grep. Scripts turn them into repeatable steps (`make run`, `make measure`) and into **tests** that print `PASS` or `FAIL`. Writing the tests in shell keeps them as close as possible to the commands in the lesson.

## Where it appears

| Path | What it does |
| --- | --- |
| `scripts/lib.sh` | Shared helpers, sourced by every other script: `check`, `build_version`, `high_critical`, `serve_and_get`, cleanup. |
| `scripts/deploy.sh` | Build v3, push it, deploy by digest, call it. |
| `scripts/sbom.sh` | Build v4 with attestations and print what they say. |
| `scripts/measure.sh` | Build v0 to v4 and write the measurements table. |
| `scripts/coverage.sh` | Enforce 95 percent coverage on the inner layers. |
| `tests/e2e/01_...sh` to `06_...sh` | One check per lesson "Done when" line. |

## How it works underneath

The shell splits a line into words, starts the first word as a program, and waits. The program's **exit code** (`0` success, other failure) is stored in `$?`. `set -e` stops the script at the first failing command, `set -u` makes using an unset variable an error, and `set -o pipefail` makes a pipeline fail if **any** command in it fails (by default only the last counts). Together: `set -euo pipefail`.

`source file` (or `. file`) runs another file's commands **in the current shell**, so its functions and variables become available. `trap COMMAND EXIT` registers a command to run when the script ends for any reason. A **function** is a named group of commands called like a program. `"$@"` expands to all of a function's arguments, each kept intact. `$(command)` captures a command's output. `${NAME:-default}` uses a default when unset. Arrays (`ITEMS=()`, `ITEMS+=(x)`) are a Bash feature, not available in plain `sh`.

## Walkthrough of this repository's use

### The helper library

```bash
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
```

- `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` finds the project folder from the library's own path. `BASH_SOURCE[0]` is the path of the file being executed (or sourced); `dirname` strips the file name; `cd ... && pwd` converts it to an absolute path.
- `export BUILDER="${BUILDER:-shrink-and-harden}"` sets a default and exports it so child programs see it.
- `CLEANUP_CONTAINERS=()` creates empty arrays that tests append to; the `cleanup` function removes everything they registered. `trap cleanup EXIT` runs it however the script ends.
- `${CLEANUP_CONTAINERS[@]+"${CLEANUP_CONTAINERS[@]}"}` expands the array only if it is set; it avoids an "unbound variable" error under `set -u` for an empty array in Bash 3.2 (the macOS version).
- `if [ -f "${ROOT}/.env" ]; then . "${ROOT}/.env"; fi` loads variables from `.env`. The `# shellcheck disable=SC1091` line tells ShellCheck that the file is not available to analyze.
- `check DESCRIPTION ACTUAL EXPECTED` prints `PASS` or `FAIL` and sets `FAILED=1`; `finish` (at the end of the library) exits with that code. `check_true` hands a comparison to `awk`.
- `seconds_of COMMAND...` records the time with a Perl one-liner (macOS `date` has no sub-second field), runs the command quietly and prints the difference.
- `export TRIVY_IMAGE="aquasec/trivy:0.58.0"` pins the vulnerability scanner's image. `FAILED=0` is the flag `check` flips. `export REGISTRY="localhost:${REGISTRY_PORT:-5057}"` builds the registry address from the port in `.env` (5057 by default).
- `say` prints a heading. `image_bytes IMAGE` asks Docker for an image's size in bytes (`--format '{{.Size}}'` selects one field). `megabytes N` converts with awk (1 MB = 1,000,000 bytes, rounded: `%.0f`).
- `build VERSION DOCKERFILE CONTEXT [args]`: `local version="$1" ...` copies the first three arguments into named local variables, `shift 3` drops them so `"$@"` holds only the extra arguments, and `docker buildx build --builder ... --load --file ... --tag svc:VERSION` builds on the project's own builder and loads the result into the local image store.
- `build_version`: `local ... extra=()` makes an empty array; `while IFS= read -r line; do extra+=("${line}"); done < <(args_for "${version}")` reads the lines that `args_for` prints into the array (`IFS=` and `-r` keep each line exactly as printed; `< <(...)` feeds the command's output to the loop without a subshell). Then `build ... "${extra[@]}" "$@"` passes every collected word as a separate argument.
- `high_critical IMAGE` runs Trivy in a container with the Docker socket mounted (`-v /var/run/docker.sock:/var/run/docker.sock`, so Trivy can read the local image) and a named volume as its database cache (`-v shrink-trivy-cache:/root/.cache/`). `--quiet --scanners vuln --format json` prints only JSON vulnerabilities. The `jq` filter collects every `.Severity`, counts the CRITICAL ones and the HIGH ones, and prints them as `critical/high` (for example `7/290`). `[.Results[]?.Vulnerabilities[]?.Severity]` means "for every result, for every vulnerability, its severity", where the `?` makes missing arrays harmless.
- `serve_and_get IMAGE PORT PATH`: `name="svc-smoke-$$"` uses `$$`, the script's process id, to make the container name unique; `-p "127.0.0.1:$2:8080"` publishes container port 8080 on the given host port, on the local machine only; `curl -fsS` fails on HTTP errors (`-f`), stays quiet but shows errors (`-sS`).
- `finish` prints `OK` or `FAILED` and exits with the flag as the exit code.

### Version-aware build helpers

```bash
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
```

`case "$1" in ... esac` chooses by pattern: `v0` gets the build argument, `v1` nothing, anything else the secret. `printf '%s\n' --secret "id=netrc,src=${ROOT}/netrc"` prints each word on its own line so the caller can read them into an array without word-splitting problems. `dockerfile_for` picks the right file with the same `case`.

### A test script

```bash
#!/usr/bin/env bash
# Done when (step 2): the image is under a quarter of its original size and still passes the smoke test.
set -euo pipefail
# shellcheck source=../../scripts/lib.sh
. "$(dirname "$0")/../../scripts/lib.sh"
cd "${ROOT}"
[ -f netrc ] || cp netrc.example netrc
CLEANUP_IMAGES+=(svc:v0 svc:v1)

build_version v0 "${ROOT}" > /dev/null 2>&1
build_version v1 "${ROOT}" > /dev/null 2>&1
v0="$(image_bytes svc:v0)"
v1="$(image_bytes svc:v1)"
say "sizes: v0 $(megabytes "${v0}") MB, v1 $(megabytes "${v1}") MB"
check_true "v1 is under a quarter of v0" "a < b / 4" "${v1}" "${v0}"
check "the v1 smoke test: GET /health" "$(serve_and_get svc:v1 18081 /health)" "ok"
finish
```

- `set -euo pipefail` at the top. `# shellcheck source=...` and `. "$(dirname "$0")/../../scripts/lib.sh"` load the library; `$0` is this script's path.
- `CLEANUP_IMAGES+=(svc:v0 svc:v1)` registers images for removal at exit.
- `build_version v0 "${ROOT}" > /dev/null 2>&1` builds quietly.
- `check_true "..." "a < b / 4" "${v1}" "${v0}"` asserts v1 is under a quarter of v0, computed by awk.
- `serve_and_get svc:v1 18081 /health` starts the image, fetches a path and prints the body; the check compares it with `ok`. `finish` ends the script with success or failure.

### The other test scripts

Each script under `tests/e2e/` starts with a comment naming the "Done when" line it proves, then the same header as above (`set -euo pipefail`, load the library, `cd "${ROOT}"`, create `netrc` from the example if missing, register images to remove).

```bash
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
```

- `build_version v0 "${ROOT}" > /dev/null 2>&1` builds the one-stage image that takes the token as a build argument.
- `docker history --no-trunc svc:v0 | grep 'demo-token-123' | cut -c1-200 | sed -n '1,2p'` lists the image's layers with their full commands (`--no-trunc`), keeps lines containing the demo token, cuts each to 200 characters and prints the first two (`sed -n '1,2p'` prints lines 1 to 2). That is the leak made visible. The check passes when at least one line contains the token (`-ge 1`).
- For v2 and v3 the loop `for version in v2 v3` checks the token is gone from the history (`grep -c ... || true` counts matches and the `|| true` stops `set -e` from aborting when the count is 0), then `docker create` makes (without starting) a container, `docker export` streams its whole file system as a tar archive, `tar -t` lists the files, and `grep -c netrc` counts any with `netrc` in the name; it must be 0. `docker rm -f` removes the container.

```bash
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
```

- `WORK="$(mktemp -d)"` makes a temporary folder; `CLEANUP_DIRS+=("${WORK}")` registers it for removal; `tar ... -cf - . | tar -xf - -C "${WORK}"` copies the project there (excluding `.git` and `docs`) so the test can edit source without touching the real tree.
- `compiled_packages LOG`: finds the build step that runs `go build` (`grep -m1` stops at the first match; `sed -E 's/^#([0-9]+) .*/\1/'` keeps the step number from a line like `#12 ...`), then counts the lines of that step that start with a number of seconds and a package name, which is how BuildKit prints each package that `go build -v` compiled. Packages restored from the cache are not listed, so the count measures the work done.
- `docker buildx prune --builder ... --filter type=exec.cachemount` empties the cache mounts so the first build is truly cold; the build uses `--no-cache` and `--progress=plain` (full log lines instead of a live display).
- The test appends a timestamped comment to `main.go` (so the change is real), rebuilds, and compares: cold must compile more than 50 packages (the standard library), warm fewer than a fifth of that. Seconds depend on the machine, so counting packages is the stable proof.
- A third build with no change must show the `go mod download` step as `CACHED`.

```bash
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
```

- `docker inspect --format '{{.Config.User}}'` reads the image's user: `nonroot:nonroot`.
- The smoke test fetches `/health` from a running container.
- `docker run --rm --entrypoint sh svc:v3 -c true ... && echo shell || echo none` tries to start a shell in the image; distroless has none, so the command fails and the check sees `none`.
- `high_critical` is run for v1 and v3. `${count_v3%%/*}` keeps the part before `/` (critical) and `${count_v3##*/}` the part after (high); `$(( a + b ))` adds them, and `check_true "a <= b"` requires v3 to have no more findings than v1.

```bash
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
```

- `grep -c '^FROM ' Dockerfile` counts the `FROM` lines; `grep -c '^FROM .*@sha256:[0-9a-f]\{64\}'` counts those that carry a digest (`@sha256:` followed by exactly 64 hexadecimal characters); the two numbers must be equal.
- The test builds an image, pushes it to the local registry as `svc:v3`, and records the digest from push's output (`sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p'` prints only the captured digest; `tail -1` takes the last such line). It builds a different image (`VERSION=other`), retags it as `v3` (`docker tag`), pushes again and records the new digest. The check requires the two digests to differ: a tag can be moved, a digest cannot.
- After deleting the local copies (`docker rmi -f`), `serve_and_get` runs the first image **by digest** (`svc@sha256:...`) and the moved tag, and `jq -r .version` reads the `version` field of the `/version` answer. By digest the answer is `v3` (the first image); by tag it is `other`.

```bash
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
```

- `docker buildx build --builder ... --sbom=true --provenance=mode=max --push ...` builds with two attestations attached and pushes to the local registry (`> /dev/null 2>&1` hides the log).
- `docker buildx imagetools inspect ... --format '{{ json .SBOM }}'` and `'{{ json .Provenance }}'` print those attestations as JSON.
- The `jq` filters: `.SPDX.packages[]` walks the SBOM's packages; `select(.name == "stdlib" or .name == "example.com/svc")` keeps two; `"\(.name) \(.versionInfo)"` prints name and version. The checks assert that both packages are listed, that the standard library has a version that looks like a Go version (`test("^go?[0-9]|^[0-9]")` is a regular-expression test; `any` is true if any item passes), that the provenance names a build type, and that the resolved dependencies include the pinned base images (`golang|distroless`, at least two).

### The measurement script

```bash
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
```

- It builds versions v0 to v3 with `forget_cache_mounts` (empty the builder's cache mounts, with a fallback to a full prune) before each cold build. `touch_source` appends a timestamped comment to `main.go` in the temporary copy, making the warm build a real one-line change.
- `what_changed` uses `case "$1" in v0) ... ;; esac` to print one line per version. `ROWS+="| ... |"$'\n'` appends a table row; `seconds_of build_version ...` times a build; `high_critical` counts findings; `docker history ... | grep -c 'demo-token-123'` counts token lines.
- v4 is built with SBOM and provenance and pushed to the registry; because that image lives there, the script pulls it (`docker pull --quiet`) before measuring it. `v4_build() { ... "$@" ... }` is a function so `seconds_of` can time it.
- The closing group writes `docs/measurements.md`: a heading, a sentence with the date, CPU architecture, Docker, buildx and scanner versions (`$(date -u +%Y-%m-%d)`, `$(uname -m)`, `docker version --format`, `docker buildx version | awk '{print $2}'`), the header and the rows.

### Waiting for a service

```bash
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
```

`for _ in $(seq 1 40)` repeats up to forty times (`_` is the throwaway variable). `body="$(curl ...)" && break` leaves the loop when curl succeeded. `sleep 0.25` waits a quarter second. `docker rm -f "${name}"` removes the container afterwards. `printf '%s' "${body}"` prints the body without a trailing newline.

## Try it yourself

1. Syntax-check every script without running it: `for f in scripts/*.sh tests/e2e/*.sh; do bash -n "$f" || echo "bad $f"; done`. Expected: no output.
2. See `set -e` and `pipefail`: `bash -c 'set -eo pipefail; false | cat; echo not-reached'; echo "exit $?"`. Expected: `exit 1`.
3. Call a helper by itself: `bash -c '. scripts/lib.sh; check "two equals two" 2 2; check "bad" 1 2'`. Expected: `PASS two equals two (2)` and `FAIL bad: got 1, expected 2`.
4. Watch cleanup: `bash -c '. scripts/lib.sh; CLEANUP_DIRS+=(/tmp/demo-dir); mkdir /tmp/demo-dir; echo done'; ls /tmp/demo-dir`. Expected: `done`, then an error that the folder is gone.

## Mistakes people make

- Unquoted variables that contain spaces.
- Forgetting `set -e` and carrying on after a failed step.
- Using Bash features in a `#!/bin/sh` script.
- Parsing `ls` or human-formatted output instead of using `--format` flags.
- Forgetting that a pipeline hides failures without `pipefail`.

## Check yourself

1. What does `set -euo pipefail` do? *Stops on errors and unset variables and fails a pipeline if any stage fails.*
2. Why `source` the library? *Its functions and variables must exist in the current shell.*
3. What does `trap cleanup EXIT` guarantee? *The cleanup function runs when the script ends, even after an error.*
4. What does `"$@"` preserve? *Each argument as a separate word, spaces included.*
5. Why a Perl one-liner for time? *macOS `date` cannot print sub-second time.*

## Further reading

- Bash reference manual: <https://www.gnu.org/software/bash/manual/bash.html>
- ShellCheck wiki: <https://www.shellcheck.net/wiki/>
- Bash 3.2 (macOS) differences: <https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html>
