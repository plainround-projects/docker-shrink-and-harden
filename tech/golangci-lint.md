# golangci-lint 2 (with gofmt and go vet)

## What it is

A **linter** reads code without running it and reports likely bugs and style problems. `golangci-lint` is a runner that bundles many Go linters and runs them together. This repository runs version **2.15.0** from the container `golangci/golangci-lint:v2.15.0-alpine`. Two simpler checks come with Go itself: `gofmt` (layout) and `go vet` (suspicious constructs).


**Words used in this note**

- **container**: A process (or a group of processes) run in isolation, with its own view of files, network and process list, but sharing the host's kernel.
- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **cache**: Saved results that are reused so slow work is not repeated.

## Why this repository uses it

The template asks for "the language's linter in CI". Go's culture is that the formatter has no options, so a diff never argues about layout, and `golangci-lint` adds checks for ignored errors, missing contexts and security.

## Where it appears

| Path | What it does |
| --- | --- |
| `.golangci.yml` | Which linters and formatters are enabled. |
| `Makefile` | `make lint` runs `gofmt -l`, `go vet ./...`, then `golangci-lint run ./...`. |
| `.github/workflows/ci.yml` | Runs `make lint`. |

## How it works underneath

golangci-lint loads the packages once, builds their syntax trees and type information, and runs each enabled **analyzer** over them. It prints `file:line:col: message (linter)`. `gofmt -l .` lists files whose layout differs from the standard; the Makefile fails if the list is not empty. `go vet` finds things such as wrong `Printf` verbs.

## Walkthrough of this repository's use

```yaml
version: "2"
linters:
  default: standard
  enable:
    - errorlint
    - gosec
    - misspell
    - revive
    - unconvert
    - bodyclose
    - noctx
    - nilerr
    - predeclared
  settings:
    revive:
      rules:
        - name: exported
        - name: package-comments
formatters:
  enable:
    - gofmt
    - goimports
```

- `version: "2"` selects the version 2 configuration format.
- `default: standard` starts from the standard set (errcheck, govet, staticcheck, ineffassign, unused). `enable:` adds more:
  - `errorlint`: use `errors.Is`/`errors.As` and `%w`, not `==` on errors.
  - `gosec`: security problems (for example listening on every interface).
  - `misspell`: spelling in comments.
  - `revive`: style; here the rules `exported` (doc comments on exported names) and `package-comments`.
  - `unconvert`: needless type conversions.
  - `bodyclose`: close HTTP response bodies.
  - `noctx`: HTTP requests and listeners must take a `context`.
  - `nilerr`: do not return nil after an error was checked.
  - `predeclared`: do not declare a variable, function, type or parameter whose name is one of Go's predeclared identifiers, which would hide the real one. Those are the built-in functions `append`, `cap`, `clear`, `close`, `complex`, `copy`, `delete`, `imag`, `len`, `make`, `max`, `min`, `new`, `panic`, `print`, `println`, `real`, `recover`; the types `any`, `bool`, `byte`, `comparable`, `complex64`, `complex128`, `error`, `float32`, `float64`, `int`, `int8`, `int16`, `int32`, `int64`, `rune`, `string`, `uint`, `uint8`, `uint16`, `uint32`, `uint64`, `uintptr`; and the constants `true`, `false`, `iota` and `nil`.
- `formatters: gofmt, goimports` check layout and import grouping.

Examples of what these rules forced in the code: `net.Listen(...)` became `(&net.ListenConfig{}).Listen(ctx, ...)` (noctx); `defer response.Body.Close()` became `defer func() { _ = response.Body.Close() }()` (errcheck wants the returned error handled, and `_ =` says "I chose to ignore it"); `fmt.Fprintln(w, ...)` became `_, _ = fmt.Fprintln(...)`; the tests listen on `127.0.0.1:0` instead of `:0` (gosec G102).

```makefile
lint: ## gofmt, go vet, golangci-lint, hadolint, shellcheck, compose config
	$(DOCKER_GO) $(GO_IMAGE) sh -c 'test -z "$$(gofmt -l .)" || { gofmt -l .; exit 1; }'
	$(DOCKER_GO) $(GO_IMAGE) go vet ./...
	docker run --rm -v "$(CURDIR)":/src -v shrink-gomod:/go/pkg/mod -v shrink-golangci:/root/.cache -w /src $(GOLANGCI_IMAGE) golangci-lint run ./...
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" $(HADOLINT_IMAGE) hadolint - < Dockerfile
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(SHELLCHECK_IMAGE) --external-sources --source-path=SCRIPTDIR scripts/*.sh tests/e2e/*.sh
	docker compose config --quiet
```

The recipe runs the Go tools inside the pinned containers; `-v shrink-golangci:/root/.cache` keeps the linter's cache between runs.

## Try it yourself

1. Run all lint steps: `make lint`. Expected: ends with `0 issues.` from golangci-lint.
2. List unformatted files: `docker run --rm -v "$PWD:/src" -w /src golang:1.26-bookworm gofmt -l .`. Expected: no output.
3. Break a rule in a copy: delete the `_ =` in `defer func() { _ = response.Body.Close() }()` and run `make lint`. Expected: `Error return value of ... is not checked (errcheck)`.
4. List enabled linters: `docker run --rm golangci/golangci-lint:v2.15.0-alpine golangci-lint linters`. Expected: enabled and disabled lists.

## Mistakes people make

- Adding `//nolint` comments to get green. This repository has none.
- Running linters only on changed files and missing a global problem.
- Formatting by hand. Run `make format`.

## Check yourself

1. What does `gofmt -l` print? *The files whose layout is not standard.*
2. What does `noctx` demand? *Network calls that take a `context`, so they can be cancelled.*
3. Why `_ = response.Body.Close()`? *It states that the ignored error is deliberate, which satisfies errcheck.*
4. What does `default: standard` mean? *Start from the standard linter set, then add the enabled ones.*
5. Where do the tools run? *In pinned containers; no Go is installed on the host.*

## Further reading

- golangci-lint: <https://golangci-lint.run/>
- Configuration (v2): <https://golangci-lint.run/usage/configuration/>
- `gofmt`: <https://pkg.go.dev/cmd/gofmt>
- `go vet`: <https://pkg.go.dev/cmd/vet>
