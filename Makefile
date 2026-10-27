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

help: ## list the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | sed -E 's/:.*## /\t/' | sort

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

format: ## apply gofmt
	$(DOCKER_GO) $(GO_IMAGE) gofmt -w .

audit: ## govulncheck: known vulnerabilities in the module and the standard library
	$(DOCKER_GO) $(GO_IMAGE) go run $(GOVULNCHECK) ./...

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
	rm -f netrc
