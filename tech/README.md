# Technology notes

These notes teach every technology this repository uses, from zero, through the repository's own files. You do not need to know any of them first. Each note explains what the technology is, why the repository uses it, where it appears, how it works underneath, and then walks through the repository's own lines one by one. Each ends with commands to try and five questions to check yourself.

## Reading order

1. The language: [Go](go.md), [Go modules](go-modules.md), [the Go standard library](go-standard-library.md).
2. The tests and checks on the code: [Go testing](go-testing.md), [golangci-lint](golangci-lint.md), [govulncheck](govulncheck.md).
3. The container world: [Docker](docker.md), [Dockerfile](dockerfile.md), [BuildKit and buildx](buildkit-and-buildx.md), [distroless images](distroless.md).
4. Shipping and proving what was shipped: [the registry and digests](docker-registry.md), [Docker Compose](docker-compose.md), [Trivy](trivy.md), [SBOM and provenance](sbom-and-provenance.md), [the netrc file](netrc.md).
5. The commands that tie it together: [Bash](bash.md), [Unix text tools](unix-text-tools.md), [Make](make.md), [jq](jq.md), [curl](curl.md), [environment variables and `.env` files](env-files.md).
6. Linting the build files: [hadolint](hadolint.md), [ShellCheck](shellcheck.md).
7. Delivery and file formats: [GitHub Actions](github-actions.md), [YAML](yaml.md), [ignore files and `.editorconfig`](ignore-files-and-editorconfig.md).

## Ten-minute shortlist

If you have ten minutes, read these three:

1. [Dockerfile](dockerfile.md): the four recipes, and the leak that the lesson is about.
2. [The netrc file](netrc.md): the made-up secret, how a build argument leaks it and how a secret mount does not.
3. [Distroless images](distroless.md): why the final image is 8 MB and has no shell.

## The files

| File | Its role in this repository |
| --- | --- |
| [go.md](go.md) | The language of the service; types, interfaces, errors, `CGO_ENABLED=0`. |
| [go-modules.md](go-modules.md) | `go.mod`, and why there is no `go.sum`. |
| [go-standard-library.md](go-standard-library.md) | `net/http`, `slog`, `context` and signals: the whole server without frameworks. |
| [go-testing.md](go-testing.md) | Table-driven tests, `httptest`, the race detector, coverage, the layer-rule test. |
| [golangci-lint.md](golangci-lint.md) | The Go linter, with `gofmt` and `go vet`. |
| [govulncheck.md](govulncheck.md) | The known-vulnerability check that moved the project to Go 1.26. |
| [docker.md](docker.md) | The engine, containers, signals, and the commands used. |
| [dockerfile.md](dockerfile.md) | The four recipes v0 to v3, `.dockerignore`, digests. |
| [buildkit-and-buildx.md](buildkit-and-buildx.md) | Secret mounts, cache mounts, the private builder, attestations. |
| [distroless.md](distroless.md) | The runtime base image with no shell. |
| [docker-registry.md](docker-registry.md) | The local registry, tags against digests, deploy by digest. |
| [docker-compose.md](docker-compose.md) | The registry and the deployed service. |
| [trivy.md](trivy.md) | The vulnerability scanner behind the counts in the table. |
| [sbom-and-provenance.md](sbom-and-provenance.md) | What is inside the image and how it was built. |
| [netrc.md](netrc.md) | The demo credentials file and the leak. |
| [bash.md](bash.md) | The scripts under `scripts/` and `tests/e2e/`. |
| [unix-text-tools.md](unix-text-tools.md) | `grep`, `sed`, `awk`, `tr`, `tar` and `perl` as used in the scripts. |
| [make.md](make.md) | The `Makefile`. |
| [jq.md](jq.md) | Reading JSON from Trivy and BuildKit. |
| [curl.md](curl.md) | The smoke tests. |
| [env-files.md](env-files.md) | `.env`, `.env.example` and the program's settings. |
| [hadolint.md](hadolint.md) | The Dockerfile linter. |
| [shellcheck.md](shellcheck.md) | The shell script linter. |
| [github-actions.md](github-actions.md) | The CI workflow. |
| [yaml.md](yaml.md) | The format of the compose file, the workflow and two linter configurations. |
| [ignore-files-and-editorconfig.md](ignore-files-and-editorconfig.md) | `.gitignore`, `.dockerignore` and `.editorconfig`. |

Versions pinned in this repository: Go 1.26 (image `golang:1.26-bookworm`, Go 1.26.10), golangci-lint 2.15.0, govulncheck 1.1.4, Docker engine 24.0.6, buildx 0.11.2 (BuildKit 0.33), registry 2, distroless static-debian12, Trivy 0.58.0, hadolint 2.12.0, ShellCheck 0.10.0.
