# Go modules (`go.mod`)

## What it is

A **module** is a group of Go packages that are versioned and released together. The file `go.mod` at the top of the project names the module and lists what it needs. It is Go's package manager file. When a module has third-party dependencies, a second file `go.sum` records their expected hashes.

## Why this repository uses it

Every Go project needs a `go.mod`. Here it also explains something about the lesson: the service has **no third-party dependency**, so `go mod download` has nothing to fetch and there is no `go.sum`. The Dockerfile still runs `go mod download` (with the build secret and a cache mount) because the first real dependency, or a private one, would need exactly that.

## Where it appears

| Path | What it does |
| --- | --- |
| `go.mod` | The module name and the Go language version. |
| `Dockerfile`, `build/history/v1.Dockerfile`, `v2.Dockerfile` | `COPY go.mod ./` then `RUN go mod download`. |
| `internal/architecture_test.go` | Uses the module path `example.com/svc/internal/` to recognize this project's imports. |

## How it works underneath

The first line `module example.com/svc` is the module's **path**: the prefix of every import of this project's packages, such as `example.com/svc/internal/domain`. The path looks like a web address by convention; it need not exist. `go 1.26` says which language version the code is written for.

`go mod download` fetches every required module into the **module cache** (`/go/pkg/mod`) and verifies it against `go.sum`. Modules come from a **module proxy** (by default `proxy.golang.org`) or, for private ones, from the version-control server, with credentials from `~/.netrc`. `go mod tidy` adds missing and removes unused requirements.

## Walkthrough of this repository's use

```text
module example.com/svc

go 1.26
```

- `module example.com/svc` is the lesson's module path. The import `example.com/svc/internal/domain` means "the folder `internal/domain` of this module".
- `go 1.26` is the minimum language version; newer toolchains will refuse to build it with older rules.
- There is no `require` block, because nothing outside the standard library is imported.

How the Dockerfile uses it:

```dockerfile
COPY go.mod ./
# The private-package token arrives as a build secret and exists only for this one command. `required=false` keeps
# the build working where there is no private package server to authenticate to (CI, a fresh clone).
RUN --mount=type=secret,id=netrc,target=/root/.netrc,required=false \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
```

- `COPY go.mod ./` copies only the module file first. With a `go.sum`, that would be copied too. The step `go mod download` therefore stays cached until the dependency list changes, not when source changes.
- `--mount=type=secret,id=netrc,target=/root/.netrc,required=false` makes the (demo) credentials file available only for this command. It is optional, so a plain clone builds without it.
- `--mount=type=cache,target=/go/pkg/mod` keeps the downloaded modules on the builder between builds.

## Try it yourself

1. Read the file: `cat go.mod`. Expected: two lines (`module example.com/svc`, `go 1.26`).
2. Check there is nothing to download: `docker run --rm -v "$PWD:/src" -w /src golang:1.26-bookworm go mod download -json`. Expected: no output.
3. List the module's packages: `docker run --rm -v "$PWD:/src" -w /src golang:1.26-bookworm go list ./...`. Expected: `example.com/svc/cmd/svc`, `example.com/svc/internal`, and the layer packages.
4. Add a dependency to see `go.sum` appear (do it in a copy): `go get golang.org/x/sync@latest`. Expected: a `require` block and a new `go.sum`.

## Mistakes people make

- Forgetting to commit `go.sum` once there are dependencies.
- Changing the module path after others import it.
- Copying all the source before `go mod download`, which wastes the layer cache.

## Check yourself

1. What is the module path for? *It is the prefix of every import of the project's packages.*
2. Why is there no `go.sum`? *There are no dependencies to verify.*
3. Where do downloaded modules go? *The module cache, `/go/pkg/mod`.*
4. Why copy `go.mod` before the source? *So the download step is cached until dependencies change.*
5. What does `go mod tidy` do? *Adds missing and removes unused requirements.*

## Further reading

- Go modules reference: <https://go.dev/ref/mod>
- Tutorial: <https://go.dev/doc/modules/gomod-ref>
