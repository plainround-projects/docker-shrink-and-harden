# 3. A secret mount for the token, and cache mounts for speed

Status: accepted, 2026-10-27

## Context

The starting point passes a private-package token as a build argument. The value is stored in the image history; deleting the file in a later layer does not remove it, because the earlier layer stays.

## Decision

`RUN --mount=type=secret,id=netrc,target=/root/.netrc,required=false`: the file exists only during `go mod download` and is never part of a layer. It is passed with `docker build --secret id=netrc,src=./netrc`. `required=false` lets the same Dockerfile build where there is no private package server, such as a fresh clone or CI. Separate cache mounts (`/go/pkg/mod`, `/root/.cache/go-build`) keep downloaded modules and compiled packages between builds; they live on the builder and are not in the image. A cache mount is for speed and a secret mount is for a value that must never be saved; they are different tools and are never swapped.

## Alternatives considered

- **`ARG` or `ENV`:** both are stored in the history. This is the mistake step 1 shows.
- **SSH agent forwarding (`--mount=type=ssh`):** the right tool for private Git over SSH; the lesson's server is an HTTP package host with a netrc login.
- **Multi-stage alone, relying on the build stage not shipping:** the final image is clean, but the token is still in the build stage's layers and in the builder's cache.

## Consequences

- `docker history --no-trunc` on v2 and later has no token line, and the e2e test checks the exported file system for a `.netrc` as well.
- The first build on a new builder downloads modules and compiles the standard library; later builds do not. `make measure` empties the cache mounts before each cold build so the comparison is fair.
