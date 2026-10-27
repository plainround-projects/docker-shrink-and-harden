# 2. Distroless static as the runtime, and the binary checks itself

Status: accepted, 2026-10-27

## Context

Step 4 asks for a minimal runtime base, non-root, with a plan for debugging without a shell. A health check is still wanted: orchestrators and `docker compose --wait` use it.

## Decision

`gcr.io/distroless/static-debian12:nonroot`, pinned by digest. The Go binary is built with `CGO_ENABLED=0`, so it needs no C library. `USER nonroot:nonroot` is explicit in the Dockerfile. There is no shell and no `curl`, so `HEALTHCHECK` runs `/app healthcheck`, a subcommand of the service binary that requests `/health` on localhost.

Debugging without a shell, in the order to try it: read `docker logs` (the service logs one line per request and per lifecycle event); `docker inspect` for state and health; `docker debug <container>` where Docker Desktop provides it; otherwise an ephemeral container that shares the target's PID and network namespaces: `docker run --rm -it --pid=container:<name> --network=container:<name> alpine sh`. A `:debug` tag of the base image (with BusyBox) is for development only and is never deployed.

## Alternatives considered

- **`scratch`:** smaller by a few hundred kilobytes, but no CA certificates, no time zone data and no `/etc/passwd` for a non-root user; the distroless static image has all three.
- **`debian:bookworm-slim` (v1, v2):** has a shell and a package manager, which is exactly the attack surface and the scanner findings v3 removes.
- **A health check with `curl` copied into the image:** adds a binary and its libraries to the image for one request.

## Consequences

- The scanner's finding count drops to the binary's own dependencies and the Go standard library.
- `docker exec -it svc sh` fails, by design. The incident runbook is in the README.
