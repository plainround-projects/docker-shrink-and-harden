# Go 1.26

## What it is

Go is a programming language made at Google for servers and command-line tools. You write source files (`.go`). The `go` command **compiles** them: it translates the whole program into one machine-code file that the computer can run directly. No Go installation is needed to run that file. This repository uses Go **1.26**, the current stable line when it was built.

Go is **statically typed** (every value has a type, checked when you compile) and has **garbage collection** (the runtime frees memory you stop using). It has no classes and no exceptions: you write functions and `struct`s, and errors are ordinary values that functions return.

## Why this repository uses it

The lesson says "a compiled service (Java, Go or similar)". Go suits it because it can produce a **static binary**: a single file with no outside libraries, which runs on a nearly empty container image (the distroless image in `Dockerfile`). That is what makes the image shrink from 937 MB to 8 MB.

## Where it appears

| Path | What it does with Go |
| --- | --- |
| `cmd/svc/main.go` | The program's entry point and wiring. |
| `internal/domain/` | The status and build-information types. Standard library only. |
| `internal/application/` | The `Service` and the `BuildInfoSource` interface. |
| `internal/infrastructure/` | Configuration, build information, logging. |
| `internal/interfaces/` | The HTTP handlers and server, and the health command. |
| `*_test.go` files | Tests, in the same folders as the code. |
| `go.mod` | The module definition (see `go-modules.md`). |

## How it works underneath

`go build` reads the package you name, finds every package it imports, compiles each one, and **links** them into one executable. Packages are folders: every `.go` file in a folder begins with `package name`. Names that start with a capital letter (`NewService`) are **exported**: other packages can use them. Lower-case names are private to the package. A folder called `internal/` is special: only code in the tree that contains the `internal` folder may import it.

A program starts at `func main()` in `package main`. Functions are values. A `struct` groups fields. An **interface** is a list of method names; any type that has those methods satisfies it, without saying so. A **goroutine** is a lightweight thread started with the `go` keyword; **channels** pass values between goroutines.

With `CGO_ENABLED=0` the compiler does not link any C code, so the binary needs no C library at all. That is what lets it run on `distroless/static`.

## Walkthrough of this repository's use

### Types, constants and methods

```go
// Package domain holds the service's vocabulary. It imports nothing outside the standard library.
package domain

import "fmt"

// Status is the answer to a health check.
type Status string

// StatusOK means the process is serving.
const StatusOK Status = "ok"

// BuildInfo identifies the binary: which version and commit it was built from and with which Go toolchain.
// It is what lets an operator match a running container to an image and to the packages listed in its SBOM.
type BuildInfo struct {
	Version   string `json:"version"`
	Commit    string `json:"commit"`
	GoVersion string `json:"goVersion"`
}

// String renders the build information on one line, for logs.
func (info BuildInfo) String() string {
	return fmt.Sprintf("version=%s commit=%s go=%s", info.Version, info.Commit, info.GoVersion)
}
```

- `type Status string` makes a new type whose underlying value is a string. `const StatusOK Status = "ok"` is its one value. The type stops you from passing any random string where a status is expected.
- `type BuildInfo struct {...}` groups three fields. The text in backquotes after each field (`json:"version"`) is a **struct tag**: it tells the JSON encoder which key name to use.
- `func (info BuildInfo) String() string` is a **method**: a function attached to a type, with the receiver `info` written before its name. `fmt.Sprintf` formats text like C's `printf`. A type with a `String()` method prints nicely.
- The comment above each exported name starts with that name: this is Go's documentation convention, and the linter `revive` checks it.

### An interface and a constructor

```go
// Package application holds the use cases and the ports they need. It depends on the domain only.
package application

import (
	"context"

	"example.com/svc/internal/domain"
)

// BuildInfoSource tells the service which binary it is.
type BuildInfoSource interface {
	Read() domain.BuildInfo
}

// Service answers the two questions an orchestrator and an operator ask: are you up, and which build are you.
type Service struct {
	source BuildInfoSource
}

// NewService returns a Service that reads its build information from source.
func NewService(source BuildInfoSource) *Service {
	return &Service{source: source}
}

// Health reports whether the service is serving. The service has no dependencies, so a running process is healthy;
// the context is part of the signature so a dependency check can be added without changing callers.
func (service *Service) Health(_ context.Context) domain.Status {
	return domain.StatusOK
}

// Version returns the identity of the running binary.
func (service *Service) Version() domain.BuildInfo {
	return service.source.Read()
}
```

- `BuildInfoSource` is an **interface** with one method `Read()`. `Service` depends on this shape, not on a concrete type, which is what lets the tests give it a fake.
- `NewService` is a **constructor** by convention: Go has no constructors, so a function that returns a ready value is called `NewX`. `&Service{source: source}` builds a struct and returns a **pointer** to it (`*Service`), so callers share one value instead of copying it.
- `func (service *Service) Health(_ context.Context)`: the receiver is a pointer. The parameter name `_` means "required by the signature but unused". A `context.Context` carries a cancel signal and deadlines through a call chain.

### Errors as values

```go
func Load(getenv func(string) string) (Config, error) {
	port, err := integer(getenv, "PORT", 8080, 1, 65535)
	if err != nil {
		return Config{}, err
	}
	seconds, err := integer(getenv, "SHUTDOWN_TIMEOUT_SECONDS", 8, 1, 60)
	if err != nil {
		return Config{}, err
	}
	level := slog.LevelInfo
	if raw := getenv("LOG_LEVEL"); raw != "" {
		if err := level.UnmarshalText([]byte(raw)); err != nil {
			return Config{}, fmt.Errorf("LOG_LEVEL must be debug, info, warn or error, got %q", raw)
		}
	}
	return Config{
		Addr:            ":" + strconv.Itoa(port),
		LogLevel:        level,
		ShutdownTimeout: time.Duration(seconds) * time.Second,
	}, nil
}

func integer(getenv func(string) string, name string, fallback, minimum, maximum int) (int, error) {
```

A function that can fail returns its result and an `error` as two values: `(Config, error)`. The caller checks `if err != nil`. `fmt.Errorf("... %q", raw)` builds an error message (`%q` prints the value in quotes). Returning early on error keeps the happy path unindented. Go has no exceptions, so every failure is visible in the code.

### Packages as layers

```go
var allowed = map[string][]string{
	"domain":         {},
	"application":    {"domain"},
	"infrastructure": {"domain", "application"},
	"interfaces":     {"domain", "application", "infrastructure"},
}
```

The dependency rule from the template is written as data and checked by a test. `go/parser` reads each file's import list; the test fails if a lower layer imports a higher one.

## Try it yourself

(There is no Go on the host; these run in the pinned container. `GO="docker run --rm -v $PWD:/src -w /src golang:1.26-bookworm"`.)

1. Version: `$GO go version`. Expected: `go version go1.26.x linux/arm64` (the x depends on the pinned image; the build used 1.26.10).
2. Build the binary: `$GO sh -c 'CGO_ENABLED=0 go build -o /tmp/svc ./cmd/svc && ldd /tmp/svc'`. Expected: `not a dynamic executable` (the binary needs no shared libraries).
3. Run the tests: `make test`. Expected: every package `ok` and the coverage lines.
4. Run the service: `make run`, then `curl -s localhost:8089/version`. Expected: `{"version":"v3","commit":"unknown","goVersion":"go1.26.10"}` (commit is `unknown` when built outside git, or a short hash).

## Mistakes people make

- Ignoring the `error` result. The linter `errcheck` fails the build on that.
- Forgetting that a method with a pointer receiver changes the original, and one with a value receiver changes a copy.
- Starting goroutines without a way to stop them. The server here stops through a `context`.
- Building a dynamic binary and putting it on an image with no C library: the container fails with "no such file or directory". `CGO_ENABLED=0` prevents it.

## Check yourself

1. What does `CGO_ENABLED=0` give you? *A binary with no dependency on C libraries, so it runs on a minimal image.*
2. How does Go signal failure? *A function returns an `error` value; the caller checks it.*
3. What makes a name exported? *A capital first letter.*
4. What is an interface in Go? *A set of method names; any type with those methods satisfies it.*
5. What does `internal/` do? *Only code in the same module tree can import packages under it.*

## Further reading

- The Go documentation (1.26): <https://go.dev/doc/>
- A Tour of Go: <https://go.dev/tour/>
- Effective Go: <https://go.dev/doc/effective_go>
- The language specification: <https://go.dev/ref/spec>
