# GNU Make

## What it is

Make runs named recipes from a file called `Makefile`. Each recipe is a **target**; a target may depend on other targets, which run first. It was made for compiling programs; here it is a menu of project commands (`make up`, `make test`, `make lint`). macOS ships GNU Make 3.81, which this file is written for.


**Words used in this note**

- **container**: A process (or a group of processes) run in isolation, with its own view of files, network and process list, but sharing the host's kernel.
- **shell**: A program that reads the commands you type (or a script's lines) and starts other programs for you. Bash is a shell.
- **image**: A read-only bundle of files and settings from which containers are started.
- **hash**: A short fingerprint computed from the bytes of a file. Change one byte and the fingerprint changes. SHA-256 is a common method; its result is called a digest.
- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **environment variable**: A named piece of text the operating system hands to a program when it starts, such as `PORT=8080`. Programs read these for their settings.
- **cache**: Saved results that are reused so slow work is not repeated.
- **mount**: To make a folder or volume appear at a chosen path inside a container.
- **registry**: A server that stores and serves images.
- **database**: A program that stores data in an organized way and answers questions about it. PostgreSQL is one.
- **volume**: Storage managed by Docker that outlives any one container.
- **terminal**: A window where you type commands as text and read the answers. The program inside it that reads your commands is the shell.

## Why this repository uses it

The template says a reader should need only `make run` and `make test`. Because no Go is installed on the host, the Makefile also hides the long `docker run` commands that run the Go tools in containers.

## Where it appears

| Path | What it does |
| --- | --- |
| `Makefile` | `up`, `run`, `test`, `lint`, `format`, `audit`, `check`, `measure`, `sbom`, `test-e2e`, `builder`, `netrc`, `down`, `clean`. |
| `.github/workflows/ci.yml` | Calls the same targets. |

## How it works underneath

A rule is `target: dependencies` followed by tab-indented recipe lines. Make runs each recipe line in a fresh shell. `.PHONY` marks targets that are names, not files, so Make always runs them. Variables: `NAME := value` (set now), `NAME ?= value` (set unless already set), read as `$(NAME)`. `-include .env` loads the file if it exists; `export` passes all variables to recipe commands. A recipe line starting with `@` is not echoed; one starting with `-` may fail without stopping Make. `$(CURDIR)` is the current folder.

## Walkthrough of this repository's use

```makefile
# make up | run | test | lint | down      (make help lists everything)
# Go is not needed on this machine: every Go tool runs in a pinned container, so a fresh clone needs only Docker.
GO_IMAGE := golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af
GOLANGCI_IMAGE := golangci/golangci-lint:v2.15.0-alpine
HADOLINT_IMAGE := hadolint/hadolint:v2.12.0
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.10.0
GOVULNCHECK := golang.org/x/vuln/cmd/govulncheck@v1.1.4
BUILDER := shrink-and-harden
REGISTRY_PORT ?= 5057
DOCKER_GO := docker run --rm -v "$(CURDIR)":/src -v shrink-gomod:/go/pkg/mod -v shrink-gobuild:/root/.cache/go-build -w /src

-include .env
export

.PHONY: help netrc builder up run test coverage lint format audit check measure sbom test-e2e down clean
```

- The pinned images are variables: `GO_IMAGE` (with its digest), `GOLANGCI_IMAGE`, `HADOLINT_IMAGE`, `SHELLCHECK_IMAGE`. Changing a tool version means changing one line.
- `GOVULNCHECK := golang.org/x/vuln/cmd/govulncheck@v1.1.4` is a Go package path with a version, not a container.
- `REGISTRY_PORT ?= 5057` lets you override the port with an environment variable.
- `DOCKER_GO := docker run --rm -v ...` is the prefix that runs a command in the Go container with the project and caches mounted.

```makefile
netrc: ## create the demo netrc (a made-up token for a pretend private package server) from netrc.example
	@[ -f netrc ] || cp netrc.example netrc
	@[ -f .env ] || cp .env.example .env

builder: ## create the BuildKit builder used for cache measurements, SBOM and provenance (docker-container driver)
	@docker buildx inspect $(BUILDER) > /dev/null 2>&1 || \
	  docker buildx create --name $(BUILDER) --driver docker-container --driver-opt network=host > /dev/null
	@docker buildx inspect $(BUILDER) --bootstrap > /dev/null

up: netrc ## start the local registry and wait until it is healthy
	docker compose up --detach --wait registry

run: up ## build the service (v3), push it, deploy it by digest and call it
	scripts/deploy.sh
```

- `netrc` copies the example credentials and `.env` if missing. `[ -f netrc ] || cp netrc.example netrc` means "test whether the file exists; if the test fails, copy". The leading `@` hides the command.
- `builder` creates the BuildKit builder only if `docker buildx inspect` fails; the backslash continues the line.
- `up: netrc` runs `netrc` first, then starts only the registry with `docker compose up --detach --wait registry`.
- `run: up` depends on `up`, then `scripts/deploy.sh` builds, pushes and deploys.

```makefile
test: ## unit tests with the race detector; domain and application must stay at 95 percent or more
	$(DOCKER_GO) $(GO_IMAGE) go test -race -cover ./...
	scripts/coverage.sh "$(DOCKER_GO) $(GO_IMAGE)"

lint: ## gofmt, go vet, golangci-lint, hadolint, shellcheck, compose config
	$(DOCKER_GO) $(GO_IMAGE) sh -c 'test -z "$$(gofmt -l .)" || { gofmt -l .; exit 1; }'
	$(DOCKER_GO) $(GO_IMAGE) go vet ./...
	docker run --rm -v "$(CURDIR)":/src -v shrink-gomod:/go/pkg/mod -v shrink-golangci:/root/.cache -w /src $(GOLANGCI_IMAGE) golangci-lint run ./...
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" $(HADOLINT_IMAGE) hadolint - < Dockerfile
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(SHELLCHECK_IMAGE) --external-sources --source-path=SCRIPTDIR scripts/*.sh tests/e2e/*.sh
	docker compose config --quiet
```

- `test` runs `go test -race -cover ./...` in the Go container, then `scripts/coverage.sh` for the 95 percent gate. The script reads the image name from the environment variable `GO_IMAGE`, which the Makefile's `export` line hands to every command it runs. `-race` turns on the race detector.
- `lint` runs `gofmt -l` (listing unformatted files and failing if any), `go vet`, `golangci-lint`, `hadolint`, `shellcheck` and `docker compose config`.
- `$$(gofmt -l .)` uses `$$` because Make treats a single `$` as its own variable; `$$` passes one `$` to the shell.

```makefile
measure: netrc builder up ## build v0 to v4, measure size, builds and scanner counts, write docs/measurements.md (about ten minutes)
	scripts/measure.sh

sbom: netrc builder up ## build v4: the service image with an SBOM and provenance, pushed to the local registry
	scripts/sbom.sh

test-e2e: netrc builder up ## the lesson's Done-when checks, one script each, against real images
```

- `measure: netrc builder up` has three prerequisites, run in order, then `scripts/measure.sh`.
- `test-e2e` loops over `tests/e2e/*.sh` in a shell `for` and stops at the first failure (`|| exit 1`).

### The remaining targets

```makefile
help: ## list the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | sed -E 's/:.*## /\t/' | sort
```

- `help` prints every target that has a `##` comment: `grep -E '^[a-z0-9-]+:.*## '` selects those lines from the Makefile (`$(firstword $(MAKEFILE_LIST))`: `MAKEFILE_LIST` names every file Make has read, and `-include .env` adds `.env` to it, so taking the first word keeps `grep` from prefixing each line with a file name), `sed -E 's/:.*## /\t/'` replaces the colon and everything up to `## ` with a tab, and `sort` orders them.

```makefile
format: ## apply gofmt
	$(DOCKER_GO) $(GO_IMAGE) gofmt -w .

audit: ## govulncheck: known vulnerabilities in the module and the standard library
	$(DOCKER_GO) $(GO_IMAGE) go run $(GOVULNCHECK) ./...
```

- `format` runs `gofmt -w .`, which rewrites Go files into the standard layout (`-w` writes the change).
- `audit` runs `govulncheck` with `go run PACKAGE@VERSION`, which downloads and runs the pinned tool for one command; it checks the module and the standard library against the Go vulnerability database.

```makefile
check: lint test ## lint plus unit tests

measure: netrc builder up ## build v0 to v4, measure size, builds and scanner counts, write docs/measurements.md (about ten minutes)
	scripts/measure.sh

sbom: netrc builder up ## build v4: the service image with an SBOM and provenance, pushed to the local registry
	scripts/sbom.sh

test-e2e: netrc builder up ## the lesson's Done-when checks, one script each, against real images
	for script in tests/e2e/*.sh; do echo "== $$script"; "$$script" || exit 1; done

down: ## stop the registry and the service; the registry volume stays
	docker compose --profile deploy down

clean: ## stop everything, delete the registry volume, the builder and the Go caches
	docker compose --profile deploy down --volumes
	-docker buildx rm $(BUILDER)
	-docker volume rm shrink-gomod shrink-gobuild shrink-golangci
```

- `check` runs `lint` then `test`.
- `measure`, `sbom` and `test-e2e` all depend on `netrc builder up` (create the demo credentials, create the BuildKit builder, start the registry), then run their script: `measure.sh`, `sbom.sh`, or every `tests/e2e/*.sh` in a loop that stops at the first failure (`|| exit 1`). `"$$script"` uses `$$` so the shell, not Make, reads the loop variable.
- `down` stops the registry and the service (the `deploy` profile); the registry volume stays. `clean` also deletes the volume, removes the builder (`docker buildx rm`) and the Go cache volumes (`docker volume rm ...`), and deletes the demo credentials file (`rm -f netrc`). The leading `-` on two lines lets them fail, for example when the builder is already gone, without stopping Make.

## Try it yourself

1. List the menu: `make help`. Expected: each target with its description.
2. See what a target would run: `make -n test`. Expected: the commands printed, nothing executed.
3. Run the Go tests: `make test`. Expected: nine `ok` lines and `coverage of internal/domain: 100.0%`.
4. Override a variable: `REGISTRY_PORT=5099 make -n up`. Expected: the printed command uses the environment but the compose file reads the port itself.

## Mistakes people make

- Spaces instead of a tab before a recipe line ("missing separator").
- A single `$` in a recipe where the shell needs `$`: use `$$`.
- Assuming recipe lines share state; each runs in its own shell.
- Forgetting `.PHONY` for names like `test`.

## Check yourself

1. What does `?=` do? *Sets a variable only if it is not already set.*
2. Why `$$(gofmt -l .)`? *Make would otherwise treat `$(` as its own syntax; `$$` passes a literal `$` to the shell.*
3. What does `run: up` mean? *`up` runs first when you run `make run`.*
4. What does a leading `@` do? *The command line is not echoed.*
5. Why does `make test` need only Docker? *The Go toolchain runs in a pinned container.*

## Further reading

- GNU Make manual: <https://www.gnu.org/software/make/manual/make.html>
- Automatic variables: <https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html>
