# Bash (shell scripts)

## What it is

A **shell** is a program that reads commands and runs other programs. **Bash** is the most common shell on Linux and the older default on macOS. A **shell script** is a text file of commands; its first line, the **shebang** (`#!/usr/bin/env bash`), says which program should run it. Every script in this repository is Bash.

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
```

- `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` finds the project folder from the library's own path. `BASH_SOURCE[0]` is the path of the file being executed (or sourced); `dirname` strips the file name; `cd ... && pwd` converts it to an absolute path.
- `export BUILDER="${BUILDER:-shrink-and-harden}"` sets a default and exports it so child programs see it.
- `CLEANUP_CONTAINERS=()` creates empty arrays that tests append to; the `cleanup` function removes everything they registered. `trap cleanup EXIT` runs it however the script ends.
- `${CLEANUP_CONTAINERS[@]+"${CLEANUP_CONTAINERS[@]}"}` expands the array only if it is set; it avoids an "unbound variable" error under `set -u` for an empty array in Bash 3.2 (the macOS version).
- `if [ -f "${ROOT}/.env" ]; then . "${ROOT}/.env"; fi` loads variables from `.env`. The `# shellcheck disable=SC1091` line tells ShellCheck that the file is not available to analyze.
- `check DESCRIPTION ACTUAL EXPECTED` prints `PASS` or `FAIL` and sets `FAILED=1`; `finish` (at the end of the library) exits with that code. `check_true` hands a comparison to `awk`.
- `seconds_of COMMAND...` records the time with a Perl one-liner (macOS `date` has no sub-second field), runs the command quietly and prints the difference.

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
