# Changelog

All notable changes to this project are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-27

### Added

- A small Go service (`GET /health`, `GET /version`, `svc healthcheck`) in layers: `domain`, `application`, `infrastructure` (configuration, build information, logging), `interfaces` (HTTP with graceful shutdown, the health command); the dependency rule is enforced by a test.
- Five versions of its image, each measured: v0 one stage on the full SDK image with the token as a build argument, v1 multi-stage, v2 secret and cache mounts, v3 distroless static and non-root with bases pinned by digest, v4 the same with an SBOM and provenance.
- A local registry in Compose, a deploy by digest, `make measure`, `make sbom`, and one end-to-end script per Done-when line.
- gofmt, go vet, golangci-lint, hadolint, shellcheck, govulncheck, and a CI workflow.
