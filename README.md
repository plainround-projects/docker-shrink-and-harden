# docker-shrink-and-harden

An image pipeline for a small Go service: a one-stage build on a full SDK image of about a gigabyte that leaks a private-package token through a build argument, taken step by step to a small, fast-to-build, secret-free image pinned by digest, deployed by digest from a local registry, and documented with an SBOM and provenance. Each version is a Dockerfile in the tree and a row of measurements, so the README tells the story in numbers.

| | |
| --- | --- |
| **Lesson** | `/prep/docker/project-shrink-and-harden`, "Shrink and harden an image pipeline" (`data-structure-explainer/src/content/tracks/docker/14-project-shrink-and-harden.md` in the Plainround app) |
| **Planned hours** | 8 |
| **Level** | Intermediate |
| **Architecture** | [ARCHITECTURE.md](ARCHITECTURE.md), decisions in [docs/adr](docs/adr) |
| **Measurements** | [docs/measurements.md](docs/measurements.md) |

## Prerequisites

| Tool | Version | Used for |
| --- | --- | --- |
| Docker with Compose v2 and buildx | 24 or newer (tested with 24.0.6, Compose v2.23 and buildx 0.11 on Docker Desktop, arm64) | every build, the registry, the tools |
| GNU Make | 3.81 or newer (the one on macOS works) | every command below |
| `jq` and `curl` | any recent | reading the SBOM, calling the service |
| Images | `golang:1.26-bookworm`, `debian:bookworm-slim`, `gcr.io/distroless/static-debian12:nonroot` and `registry:2`, all pinned by digest; `golangci/golangci-lint:v2.15.0-alpine`, `hadolint/hadolint:v2.12.0`, `koalaman/shellcheck:v0.10.0`, `aquasec/trivy` for the checks and the scanner | pulled by Docker on first use |

No Go toolchain is needed on the machine: every Go tool runs in a pinned container. No cloud account and no real secrets: the "private package token" is the made-up `demo-token-123` from the lesson, and nothing in this project contacts the host it is for. Port 5057 (the registry) and 8089 (the deployed service) must be free; both can be changed in `.env`. The registry uses 5057, not the lesson's 5000, because macOS keeps 5000 for AirPlay Receiver.

## Setup, run, test, stop

```bash
make up           # create netrc and .env from the examples, start the local registry, wait until it is healthy
make run          # build v3, push it, deploy it from the registry by digest, call /health and /version
make sbom         # build v4: the same Dockerfile with an SBOM and provenance, pushed; list what is inside
make measure      # build v0 to v4 and measure each (size, cold and warm builds, scanner counts, token in history)
make test         # unit tests with the race detector; domain and application stay at 95 percent or more
make test-e2e     # one script per Done-when line, against real images
make lint         # gofmt, go vet, golangci-lint, hadolint, shellcheck, compose config
make audit        # govulncheck on the module and the standard library
make down         # stop the registry and the service; the registry volume stays
```

`make help` lists every target. `make measure` and `make test-e2e` take several minutes the first time: they build five images without cache.

What `make run` prints (digests and times vary):

```text
pushed localhost:5057/svc:v3 as sha256:31b09ac7cef0c4c6f01ef35e38f0bffd7056f5762ddc0db7517ca0197579d4e6

== Deploy by digest: the name below cannot change meaning, even if the tag v3 is moved
GET /health  -> ok
GET /version -> {"version":"v3","commit":"unknown","goVersion":"go1.26.10"}
user         -> nonroot:nonroot
health       -> healthy
```

## Done when: the lesson's checklist and the proof for each line

| # | Done when (from the lesson) | Command | What proves it |
| --- | --- | --- | --- |
| 1 | You have size, cold build, warm build and vulnerability counts for every version; `docker history --no-trunc` on the first image shows the token. | `make measure`, then `tests/e2e/01_token_leak_and_secret_mount.sh` | The table below, one row per version. The test asserts that `docker history --no-trunc svc:v0` contains `demo-token-123` (the line is quoted in "The token leak" below). |
| 2 | The image is under a quarter of its original size and still passes the smoke test. | `tests/e2e/02_multistage_size_and_smoke.sh` | Builds v0 and v1, asserts `size(v1) < size(v0) / 4`, runs v1 and asserts `GET /health` answers `ok`. |
| 3 | A warm build after a code change takes a fraction of the original time, and `docker history` no longer shows the token anywhere. | `tests/e2e/03_warm_build_uses_the_cache.sh`, `tests/e2e/01_...sh` | The first builds v2 cold, changes one line of `cmd/svc/main.go`, builds again, asserts the warm build is under half of the cold one and that the `go mod download` step is `CACHED` on an unchanged rebuild. The second asserts no token line in the history of v2 and v3 and no `netrc` file in their exported file systems. |
| 4 | The scanner's count drops, the image runs as non-root on a minimal base, and the README says which debugging approach is used without a shell. | `tests/e2e/04_distroless_nonroot_fewer_findings.sh` | `Config.User` is `nonroot:nonroot`; there is no shell (`docker run --entrypoint sh` fails); critical plus high findings for v3 are not above v1's. The debugging plan is in "Debugging without a shell" below. |
| 5 | Retagging `latest` to a different image does not change what your deploy command runs. | `tests/e2e/05_digest_pinning.sh`, `make run` | Every `FROM` carries a digest. The test pushes v3, pushes a different image under the same tag (the digest changes), and shows `docker run localhost:5057/svc@<first digest>` still reports `version: v3` while the tag now runs `other`. |
| 6 | You can answer "does this image contain library X, and which version?" from the SBOM alone, and the README has a before-and-after table. | `make sbom`, `tests/e2e/06_sbom_and_provenance.sh` | `docker buildx imagetools inspect localhost:5057/svc:v4 --format '{{ json .SBOM }}'` lists the packages (`stdlib` with the Go version, and the service module); `.Provenance` names the build. The before-and-after table is below. |
| 7 | The README table tells the story in numbers. | `make measure` | The table below. |

### The numbers

| Version | What changed | Image size | Cold build | Warm build (1-line change) | Scanner: critical/high | Token lines in `docker history` |
| --- | --- | --- | --- | --- | --- | --- |
| v0 | one stage on the full SDK image, token as a build argument | 937 MB | 24.75 s | 26.96 s | 7/290 | 2 |
| v1 | multi-stage, debian slim runtime | 106 MB | 26.38 s | 21.11 s | 1/56 | 0 |
| v2 | secret mount for the token, cache mounts | 106 MB | 29.88 s | 7.83 s | 1/56 | 0 |
| v3 | distroless static, non-root, bases pinned by digest | 8 MB | 12.09 s | 7.57 s | 0/0 | 0 |
| v4 | v3 plus SBOM and provenance | 8 MB | 18.34 s | 6.89 s | 0/0 | 0 |

Measured by `make measure` (arm64, Docker 24.0.6, buildx 0.11, Trivy 0.58 with the vulnerability database of 2026-10-27), each warm build after a different one-line change. Cold: no layer cache and empty cache mounts on the project's own builder, base images already pulled. Warm: one line of `cmd/svc/main.go` changed. The story is in the ratios: 937 MB to 8 MB (about 117 times smaller); critical and high findings from 7 and 290 to 0 and 0; the token in two lines of the v0 history and in none after; the warm build from 27 s (v0, nothing survives a source change) to 7.6 s, of which about six seconds is the fixed cost of loading the image into the local Docker. The compile work itself is visible without a stopwatch: `tests/e2e/03_warm_build_uses_the_cache.sh` counts the packages `go build -v` compiles, 196 for a cold build and 1 after a one-line change. The cold times do not fall as fast as the lesson's example because this module has no third-party dependency to download. Absolute seconds depend on the machine and the day; the scanner's counts age with its database; the ratios do not.

### The token leak, and its absence

```text
$ docker history --no-trunc svc:v0 | grep demo-token
<missing>   ...   RUN |1 PKG_TOKEN=demo-token-123 /bin/sh -c echo "machine packages.internal.example login ci password ${PKG_TOKEN}" > /root/.netrc && go mod download && go build -o /app ./cmd/svc
<missing>   ...   ARG PKG_TOKEN=demo-token-123
$ docker history --no-trunc svc:v2 | grep -ci demo-token
0
```

Deleting the `.netrc` in a later layer would not help: the history keeps the earlier layer, and the build argument is recorded as an `ARG` line as well.

### The digest test

```text
v3 was sha256:2b51f092c1652dbe86b8c6ad3c05b5a53444d81352c749945aef3ab98371ea03; after the move it is sha256:b901581072ed4f470d903de659c55bdb0a2725f2c761a17987c8b60d874d48b0
by digest: {"version":"v3","commit":"unknown","goVersion":"go1.26.10"}
by tag:    {"version":"other","commit":"unknown","goVersion":"go1.26.10"}
```

The tag `v3` now runs a different image; the deploy that names the first digest still runs the first one. A bot such as Renovate or Dependabot can open a pull request when a new digest appears, so pinning does not freeze the project.

### The SBOM answers a question without opening the image

```text
# Packages in the SBOM
base-files 12.4+deb12u15
ca-certificates 20250419~deb12u1
example.com/svc UNKNOWN
media-types 10.0.0
netbase 6.4
sbom null
stdlib go1.26.10
tzdata 2026b-0+deb12u1
# Does the image contain the Go standard library, and which version?
stdlib go1.26.10
# Provenance: what built this image, and from which pinned inputs
build type: https://github.com/moby/buildkit/blob/master/docs/attestations/slsa-definitions.md
builder: 
input: pkg:docker/docker/buildkit-syft-scanner@stable-1?platform=linux%2Farm64 sha256:873a7458c3c8ac8e32c...
input: pkg:docker/golang@1.26-bookworm?digest=sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af&platform=linux%2Farm64 sha256:632dff7351799a5a995...
input: pkg:docker/gcr.io/distroless/static-debian12@nonroot?digest=sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab&platform=linux%2Farm64 sha256:afa5c872c891853ca7f...
```

`stdlib go1.26.10` answers "which Go standard library is inside"; a CVE announcement for a Go release can be checked against the SBOM without pulling or unpacking the image, and the provenance lists the digests of the base images the build consumed.

### Debugging without a shell

The distroless image has no shell, no package manager and no `curl`, so `docker exec -it svc sh` fails by design. In the order to try:

1. **Logs and state.** The service logs one line per request and per lifecycle event: `docker logs svc`. `docker inspect svc` shows the exit code, the health status and the last health output.
2. **`docker debug svc`** where Docker Desktop provides it: a shell with tools attached to the running container without changing the image.
3. **An ephemeral container in the same namespaces:** `docker run --rm -it --pid=container:svc --network=container:svc alpine sh` gives a shell that sees the same processes and network (`wget -qO- localhost:8080/health`). Add `--cap-add SYS_PTRACE` to attach a debugger.
4. **A `:debug` tag of the base image** (it adds BusyBox) in development only, never deployed.

## Stretch goals

| Stretch (from the lesson) | Built? |
| --- | --- |
| Build for amd64 and arm64 in one command and push a multi-platform manifest. | No. The binary is built with `CGO_ENABLED=0`, so it is portable, and [ARCHITECTURE.md](ARCHITECTURE.md) shows the command; it needs QEMU emulation for the other architecture, which the Docker Desktop builder provides but this project does not rely on. |
| Sign the image and verify the signature before running it. | No. [ARCHITECTURE.md](ARCHITECTURE.md) names the step. |
| Add a CI job that fails when a new critical vulnerability appears in the runtime image. | Partly. CI runs `govulncheck` on every push (`make audit`). A scanner gate on the built image is described in [ARCHITECTURE.md](ARCHITECTURE.md) and not wired in, since the scanner's database changes daily and would make an unrelated push fail. |

## What is simplified for teaching

Only what the lesson scopes out, plus where this build differs from the lesson's text:

- The private package server is imaginary. The secret mount is exercised on every build, but no request carries the token.
- The service has no third-party module, as in the lesson, so the module cache mount has nothing to cache; the warm-build speedup comes from the compiler cache and the layer order. The mount stays because the Dockerfile should not change when a first dependency arrives.
- One platform (the machine's own, arm64 here); the lesson's numbers are from amd64 and differ in size.
- The registry is local, plain HTTP, no authentication, on loopback only.
- The service is a little larger than the lesson's `main.go` (a `/version` route, graceful shutdown, a health subcommand, layers), so the same image can be identified by `/version`, which the digest test needs.
- Go 1.26 (the current stable line) and `golang:1.26-bookworm` replace the lesson's Go 1.23. The lesson's v0 base is `golang:1.23`; the digest-pinned `golang:1.26-bookworm` is the equivalent full SDK image today, and the newer line matters: `govulncheck` reports ten standard-library vulnerabilities for Go 1.25.14 that are fixed only in 1.26.
- The scanner is Trivy, because Docker Scout needs a Docker account. Counts depend on the scanner database of the day.
- The lesson's `Dockerfile` for v1 and v2 builds `.`; these build `./cmd/svc`, since the service has a layered tree.
- Times are from one laptop that was busy with other work; the order of the rows and the ratios are what matter.

## Project structure

```text
cmd/svc/             main: composition root. `svc` serves; `svc healthcheck` checks a running instance.
internal/
  domain/            Status and BuildInfo. Depends on nothing outside the standard library.
  application/       Service (Health, Version) and the BuildInfoSource port. Depends on domain only.
  infrastructure/    config (environment), buildinfo (stamped version and commit), logging. Depends on application and domain.
  interfaces/        httpapi (routes, request log, panic recovery, graceful server), cli (the health command).
                     Depends on everything below; nothing depends on it.
  architecture_test.go  fails when a layer imports one above it, or domain/application import a third-party package.
build/history/       v0, v1 and v2 Dockerfiles: the first three versions, kept for the measurements. Not linted.
Dockerfile           v3 (and v4, built with an SBOM and provenance): the image that ships.
scripts/             deploy.sh, sbom.sh, measure.sh, coverage.sh, lib.sh.
tests/e2e/           one script per Done-when line.
docs/                measurements.md (generated), adr/ (decision records).
docker-compose.yml   the local registry and the deployed service (profile deploy).
netrc.example        the demo credentials file (a made-up token); `make up` copies it to netrc, which git ignores.
go.mod               the module (no third-party dependencies).
.golangci.yml        linter configuration.     .hadolint.yaml  Dockerfile lint configuration.
Makefile             the only commands a reader needs (make help).
```

The dependency rule (domain depends on nothing; application on domain; infrastructure and interfaces on both; nothing on interfaces) is enforced by `internal/architecture_test.go` in `make test`.

## Troubleshooting

- **`make up` cannot bind port 5057:** set `REGISTRY_PORT` in `.env` (and use the same value in `localhost:<port>/svc`).
- **`docker buildx build --push` cannot reach `localhost:5057`:** the builder needs host networking. `make builder` creates it with `--driver-opt network=host`; on Docker Desktop that reaches the registry's published port.
- **The scanner reports zero or fails to download its database:** the first run downloads about 70 MB; run `make measure` again when you are online.
- **A cold build is not cold:** the cache mounts live on the `shrink-and-harden` builder. `make measure` prunes them first (`docker buildx prune --builder shrink-and-harden --filter type=exec.cachemount`); `make clean` removes the builder.

## Author and license

Written by Sumit Srivastava. Released under the MIT License, see [LICENSE](LICENSE). Changes are in [CHANGELOG.md](CHANGELOG.md).
