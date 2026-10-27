# Dockerfile (multi-stage, secrets, cache mounts, digests)

## What it is

A **Dockerfile** is a text recipe for building a **Docker image**: a read-only bundle of files (a minimal operating system folder tree plus your program). Docker runs the instructions from top to bottom; each instruction that changes files saves a **layer**, a stored difference, and later builds reuse unchanged layers. This repository keeps **four** Dockerfiles that tell one story, each a step better than the last.

## Why this repository uses it

The lesson is "shrink and harden an image": 937 MB with a leaked token down to 8 MB with none, pinned by digest. Each step is a Dockerfile you can build and measure.

## Where it appears

| Path | What it is |
| --- | --- |
| `build/history/v0.Dockerfile` | The starting point: one stage on the full SDK image, token as a build argument (the mistake). |
| `build/history/v1.Dockerfile` | Multi-stage: compile in one stage, ship a binary on a slim Debian. |
| `build/history/v2.Dockerfile` | Adds a secret mount for the token and cache mounts. |
| `Dockerfile` | v3 (and v4, when built with an SBOM and provenance): distroless, non-root, bases pinned by digest, health check. |
| `.dockerignore` | What is not sent to the builder. |

## How it works underneath

`docker build` sends the **build context** (the folder minus ignored files) to the builder, which starts from the `FROM` image. For each instruction it computes a **cache key** from the instruction text, its inputs (for `COPY`, the files' content) and the previous layer. A match reuses the layer. The first miss, and everything after it, runs again. So: put what changes least first.

A **multi-stage build** has several `FROM` lines; `COPY --from=build` brings files from an earlier stage and only the last stage becomes the image. The compiler, the source and the module cache stay behind.

A **build argument** (`ARG`) is stored in the image history, readable by anyone who can pull the image. A **secret mount** (`RUN --mount=type=secret`) makes a file exist only while that one command runs and is never saved in a layer. A **cache mount** (`RUN --mount=type=cache`) keeps a folder on the builder between builds; it is never part of the image.

## Walkthrough of this repository's use

### v0: the mistake

```dockerfile
# v0: the starting point, as the lesson gives it. One stage on the full SDK image, and the private-package token
# passed as a build argument, which is the mistake: the value is stored in the image history for ever.
# Kept for the measurements and the history check; it is deliberately not linted.
FROM golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af
ARG PKG_TOKEN
WORKDIR /src
COPY . .
RUN echo "machine packages.internal.example login ci password ${PKG_TOKEN}" > /root/.netrc && go mod download && go build -o /app ./cmd/svc
ENTRYPOINT ["/app"]
```

- `FROM golang:1.26-bookworm@sha256:...` is the full Go SDK image (about 900 MB: compiler, Git, C tools).
- `ARG PKG_TOKEN` declares a build argument; the build is run with `--build-arg PKG_TOKEN=demo-token-123`.
- `COPY . .` puts the whole project in the image, so the source stays in the final image too.
- The `RUN` writes the token into `/root/.netrc` so `go mod download` could authenticate to a private package server, then builds the program. Both the `ARG` line and this `RUN` line (with the value) appear in `docker history`. Deleting the file later would not remove them: the earlier layer still exists.

### v3: the shipped Dockerfile

```dockerfile
# The service image (v3 in the lesson's table, and v4 when built with an SBOM and provenance: `make sbom`).
# Compile in a build stage on the SDK image; ship only a static binary on a distroless base that has no shell, no
# package manager and runs as UID 65532. Both bases are pinned by digest; the tag stays beside the digest for people.
FROM golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af AS build
ARG VERSION=dev
ARG COMMIT=unknown
WORKDIR /src
COPY go.mod ./
# The private-package token arrives as a build secret and exists only for this one command. `required=false` keeps
# the build working where there is no private package server to authenticate to (CI, a fresh clone).
RUN --mount=type=secret,id=netrc,target=/root/.netrc,required=false \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -v -trimpath -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" -o /out/app ./cmd/svc

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
# A distroless image has no shell or curl, so the binary checks itself.
HEALTHCHECK --interval=15s --timeout=3s --start-period=3s --retries=3 CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
```

- Stage `build`: `ARG VERSION=dev` and `ARG COMMIT=unknown` are harmless build arguments (not secrets) that are stamped into the binary.
- `COPY go.mod ./` first, then `go mod download` with a **secret mount** and a **cache mount**. `required=false` makes the secret optional so a plain clone still builds.
- `COPY . .` comes after, because source changes often.
- `CGO_ENABLED=0 go build -v -trimpath -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" -o /out/app ./cmd/svc`: `CGO_ENABLED=0` makes a static binary; `-v` prints each package as it compiles (the e2e test counts them: 196 cold, 1 warm); `-trimpath` removes your folder names from the binary; `-ldflags` passes flags to the **linker**: `-s -w` strips debug tables to shrink the file, and `-X main.version=...` sets a string variable in `package main` at link time.
- `FROM gcr.io/distroless/static-debian12:nonroot@sha256:...` is the runtime: no shell, no package manager, a non-root user (see `distroless.md`).
- `COPY --from=build /out/app /app` is the only thing brought across.
- `USER nonroot:nonroot` runs as that user. `EXPOSE 8080` documents the port.
- `HEALTHCHECK ... CMD ["/app", "healthcheck"]`: there is no shell or `curl`, so the binary checks itself.
- `ENTRYPOINT ["/app"]` in exec form makes the Go program PID 1, so it receives `SIGTERM` from `docker stop`.

### Pinning by digest

Both `FROM` lines carry `tag@sha256:...`. The tag is for people; the digest is a fingerprint of the exact bytes and cannot be moved. The test `tests/e2e/05_digest_pinning.sh` counts `FROM` lines and the number that carry a 64-hex-digit digest, and they must be equal.

### `.dockerignore`

```text
.git
.github
.env
.env.*
!.env.example
netrc
docs
tests
scripts
build
*.md
Makefile
docker-compose.yml
.golangci.yml
.hadolint.yaml
```

`netrc` (the demo credentials), `.env`, `.git`, tests, docs, scripts and `build/` never reach the builder. Without that, `COPY . .` would copy `netrc` into a layer.

## Try it yourself

1. Build v3: `make run` (it builds, pushes and deploys). Expected: `pushed localhost:5057/svc:v3 as sha256:...` and a healthy container.
2. Look at the history of v0 after `make measure`: `docker history --no-trunc svc:v0 | grep demo-token`. Expected: two lines, the `RUN` and the `ARG`.
3. Check v2 and v3: `docker history --no-trunc svc:v3 | grep -ci demo-token`. Expected: `0`.
4. Compare sizes: `docker image ls svc`. Expected: v0 about 937 MB, v1 and v2 about 106 MB, v3 about 8 MB.
5. Lint it: `make lint`. Expected: hadolint prints nothing.

## Mistakes people make

- Passing secrets with `--build-arg` or `ENV`.
- Copying the whole build stage into the final stage, which brings the compiler along.
- A dynamic binary on an image with no C library: "no such file or directory" at start.
- Using a cache mount for a secret, or a secret mount for a cache. They are different tools.
- Pinning by tag only. A tag can move.
- Choosing a no-shell image with no plan for debugging (see the README).

## Check yourself

1. Why is `ARG PKG_TOKEN` a leak? *Its value is stored in the image history.*
2. What does a secret mount guarantee? *The file exists only during that command and is never saved in a layer.*
3. What does `-X main.version=...` do? *Sets a string variable in the program at link time.*
4. Why does the final image have an exec-form `ENTRYPOINT`? *So the program is PID 1 and gets `SIGTERM`.*
5. What does a digest give that a tag does not? *A fixed identity: the same name always means the same bytes.*

## Further reading

- Dockerfile reference: <https://docs.docker.com/reference/dockerfile/>
- Build secrets: <https://docs.docker.com/build/building/secrets/>
- Cache mounts: <https://docs.docker.com/build/cache/optimize/#use-cache-mounts>
- Multi-stage builds: <https://docs.docker.com/build/building/multi-stage/>
- Go command `go build` flags: <https://pkg.go.dev/cmd/go#hdr-Compile_packages_and_dependencies>
