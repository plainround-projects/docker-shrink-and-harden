# Go 1.26

## What it is

Go is a programming language made at Google for servers and command-line tools. You write source files (`.go`). The `go` command **compiles** them: it translates the whole program into one machine-code file that the computer can run directly. No Go installation is needed to run that file. This repository uses Go **1.26**, the current stable line when it was built.

Go is **statically typed** (every value has a type, checked when you compile) and has **garbage collection** (the runtime frees memory you stop using). It has no classes and no exceptions: you write functions and `struct`s, and errors are ordinary values that functions return.


**Words used in this note**

- **compiler**: A program that turns source code into machine code that the computer can run directly.
- **binary**: A file of machine code that the computer runs directly, as opposed to text that another program must read.
- **container**: A process (or a group of processes) run in isolation, with its own view of files, network and process list, but sharing the host's kernel.
- **image**: A read-only bundle of files and settings from which containers are started.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **thread**: A line of execution inside a process. One process can run several threads, and they share its memory.
- **JSON**: A text format for data. An object is `{"name": "value"}`, a list is `[1, 2]`; values are strings, numbers, `true`, `false` or `null`.
- **signal**: A short message the kernel delivers to a process. SIGTERM (number 15) politely asks it to stop; SIGKILL (number 9) cannot be caught and ends it at once.
- **layer**: One step of an image build, stored as its own set of file changes. Unchanged layers are reused from the cache.
- **standard output**: Where a program writes its normal text (standard output, stdout) and its error text (standard error, stderr). A terminal shows both. `>` sends output to a file and `|` sends it to another program.
- **environment variable**: A named piece of text the operating system hands to a program when it starts, such as `PORT=8080`. Programs read these for their settings.
- **process**: A running program. The operating system gives each process a number (its process id, or PID), its own memory and its own list of open files.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **shell**: A program that reads the commands you type (or a script's lines) and starts other programs for you. Bash is a shell.
- **hash**: A short fingerprint computed from the bytes of a file. Change one byte and the fingerprint changes. SHA-256 is a common method; its result is called a digest.

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

### Every Go source file, whole

The sections above show the most instructive parts. Here are the files that are not quoted whole elsewhere, with every line explained. Some Go words first. Every `.go` file starts with `package name`; the files in one folder share a package. `import ( ... )` lists the packages the file uses; a path such as `example.com/svc/internal/domain` is this module's own package (the module name is in `go.mod`), the others are the standard library. A line starting with `//` is a comment; a comment directly above a declaration documents it. `func name(args) result { ... }` declares a function. `:=` declares a variable and gives it a value; `=` assigns to an existing one. `defer f()` runs `f` when the surrounding function ends. `_` is the blank name: it throws a value away. `nil` means "no value" (for errors: no error).

#### `cmd/svc/main.go`: the entry point

```go
// Command svc is a small HTTP service with a health route. `svc` serves; `svc healthcheck` checks a running one.
package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"example.com/svc/internal/application"
	"example.com/svc/internal/infrastructure/buildinfo"
	"example.com/svc/internal/infrastructure/config"
	"example.com/svc/internal/infrastructure/logging"
	"example.com/svc/internal/interfaces/cli"
	"example.com/svc/internal/interfaces/httpapi"
)

// version and commit are stamped by the Dockerfile: go build -ldflags "-X main.version=... -X main.commit=...".
var (
	version = "dev"
	commit  = ""
)

func main() {
	os.Exit(run(os.Args[1:], os.Getenv, os.Stderr))
}

// run is main without the process exit, so the wiring can be tested.
func run(args []string, getenv func(string) string, stderr io.Writer) int {
	settings, err := config.Load(getenv)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "configuration error:", err)
		return 2
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if len(args) > 0 && args[0] == "healthcheck" {
		if err := cli.Healthcheck(ctx, http.DefaultClient, "http://127.0.0.1"+settings.Addr+"/health"); err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	}

	logger := logging.New(stderr, settings.LogLevel)
	service := application.NewService(buildinfo.NewReader(version, commit))
	logger.Info("starting", "build", service.Version().String())
	listener, err := (&net.ListenConfig{}).Listen(ctx, "tcp", settings.Addr)
	if err != nil {
		logger.Error("listen", "error", err)
		return 1
	}
	if err := httpapi.Serve(ctx, listener, httpapi.NewHandler(service, logger), settings.ShutdownTimeout, logger); err != nil {
		logger.Error("serve", "error", err)
		return 1
	}
	logger.Info("stopped")
	return 0
}
```

- `package main` marks a program (not a library). The doc comment above it says what the command does: `svc` serves, `svc healthcheck` checks a running instance.
- The imports bring in the standard library (`context`, `fmt`, `io`, `net`, `net/http`, `os`, `os/signal`, `syscall`) and the four layers of this module.
- `var ( version = "dev"; commit = "" )` declares two package-level variables. The Dockerfile overwrites them at build time with the linker flags `-X main.version=...` and `-X main.commit=...`, so the binary knows which version it is without reading any file.
- `func main()` is where the program starts. `os.Exit(run(os.Args[1:], os.Getenv, os.Stderr))` calls `run` with the command-line arguments after the program name (`os.Args[1:]`), the function that reads environment variables (`os.Getenv`), and standard error, and exits with the number `run` returns. Keeping `main` this small lets tests call `run` directly.
- `run(args []string, getenv func(string) string, stderr io.Writer) int` takes its inputs as parameters instead of reading globals. A parameter of type `func(string) string` is a function: tests pass a fake one.
- `settings, err := config.Load(getenv)`: functions that can fail return a result and an `error`. `if err != nil { ... }` handles it. On a bad configuration the program prints `configuration error: ...` to standard error (`_, _ = fmt.Fprintln(...)` discards the two results the linter would otherwise flag) and returns 2.
- `ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)` creates a **context** (a handle that carries cancellation) that is cancelled when the process receives SIGINT (Ctrl-C) or SIGTERM (`docker stop`). `defer stop()` releases the signal registration at the end.
- `if len(args) > 0 && args[0] == "healthcheck"` is the second mode: call `cli.Healthcheck` against `http://127.0.0.1` plus the configured address plus `/health`, print any error and return 1, or return 0.
- Otherwise: `logging.New(stderr, settings.LogLevel)` builds the logger, `application.NewService(buildinfo.NewReader(version, commit))` builds the service from the stamped values, and `logger.Info("starting", "build", ...)` logs one line with the build identity.
- `(&net.ListenConfig{}).Listen(ctx, "tcp", settings.Addr)` opens the TCP port. Failing to listen (for example because the port is taken) is logged and returns 1.
- `httpapi.Serve(ctx, listener, httpapi.NewHandler(service, logger), settings.ShutdownTimeout, logger)` runs the server until the context is cancelled, then shuts it down gracefully within the timeout. A clean stop logs `stopped` and returns 0.

#### `internal/infrastructure/config/config.go`

```go
// Package config reads the service's settings from the environment and validates them once, at start.
package config

import (
	"fmt"
	"log/slog"
	"strconv"
	"time"
)

// Config is everything the service reads from its environment.
type Config struct {
	Addr            string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
}

// Load reads PORT (default 8080), LOG_LEVEL (default info) and SHUTDOWN_TIMEOUT_SECONDS (default 8) through getenv.
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
	raw := getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be an integer, got %q", name, raw)
	}
	if value < minimum || value > maximum {
		return 0, fmt.Errorf("%s must be between %d and %d, got %d", name, minimum, maximum, value)
	}
	return value, nil
}
```

- `Config` is a **struct**: a group of named fields. `Addr` is the listen address (`":8080"`: all interfaces, port 8080), `LogLevel` is a `slog.Level`, `ShutdownTimeout` a `time.Duration`.
- `Load(getenv func(string) string) (Config, error)` returns two values. It reads `PORT` (default 8080, between 1 and 65535) and `SHUTDOWN_TIMEOUT_SECONDS` (default 8, between 1 and 60) through the helper `integer`, returning `Config{}, err` (an empty config and the error) at the first problem.
- `level := slog.LevelInfo` is the default. `if raw := getenv("LOG_LEVEL"); raw != ""` declares `raw` and tests it in one statement. `level.UnmarshalText([]byte(raw))` parses `debug`, `info`, `warn` or `error` (and rejects anything else); the error message then lists the valid words.
- The final `return Config{...}, nil` builds the result: `":" + strconv.Itoa(port)` turns the number into text; `time.Duration(seconds) * time.Second` turns a number into a duration.
- `integer` returns `fallback` when the variable is empty, `strconv.Atoi` converts text to a number (and fails on text that is not a number), and the range check names the variable in the error. `%s`, `%q` and `%d` in `fmt.Errorf` are placeholders for a string, a quoted string and a whole number.

#### `internal/infrastructure/buildinfo/buildinfo.go`

```go
// Package buildinfo reports the build's identity: values the Dockerfile stamps with the linker, and the Go version.
package buildinfo

import (
	"runtime"

	"example.com/svc/internal/domain"
)

// Reader implements application.BuildInfoSource.
type Reader struct {
	// Version is set by the Dockerfile with -ldflags "-X main.version=...", then passed in by main.
	Version string
	// Commit is set the same way (-X main.commit=...); empty means the build did not record one.
	Commit string
}

// NewReader returns a Reader for the stamped version and commit.
func NewReader(version, commit string) Reader {
	return Reader{Version: version, Commit: commit}
}

// Read returns the stamped values and the Go version the binary was compiled with. An unstamped commit is "unknown".
func (reader Reader) Read() domain.BuildInfo {
	commit := reader.Commit
	if commit == "" {
		commit = "unknown"
	}
	return domain.BuildInfo{Version: reader.Version, Commit: commit, GoVersion: runtime.Version()}
}
```

- `Reader` holds the two stamped strings. `NewReader` is a constructor function (Go has no constructors; by convention a function called `NewX` returns an X).
- `func (reader Reader) Read() domain.BuildInfo` is a **method**: a function with a receiver `(reader Reader)` written before its name. Because `Reader` has a `Read()` method returning `domain.BuildInfo`, it satisfies the `BuildInfoSource` interface in the application layer, without ever naming it.
- An empty commit becomes `"unknown"`. `runtime.Version()` is the Go toolchain version the binary was compiled with (for example `go1.26.10`), read from the binary itself.

#### `internal/infrastructure/logging/logging.go`

```go
// Package logging builds the service's structured logger.
package logging

import (
	"io"
	"log/slog"
)

// New returns a logger that writes one key=value line per event to out.
func New(out io.Writer, level slog.Level) *slog.Logger {
	return slog.New(slog.NewTextHandler(out, &slog.HandlerOptions{Level: level}))
}
```

`slog` is Go's structured-logging package. `slog.NewTextHandler(out, &slog.HandlerOptions{Level: level})` formats each event as one line of `key=value` pairs and drops events below `level`. The function returns a `*slog.Logger` (a pointer to a logger). `io.Writer` is the interface of anything you can write bytes to: standard error in production, a buffer in tests.

#### `internal/interfaces/cli/healthcheck.go`

```go
// Package cli holds the service's command-line subcommands.
package cli

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

// Healthcheck requests url and returns nil only for a 200 answer. It is the container's HEALTHCHECK: a distroless
// image has no shell and no curl, so the service binary checks itself.
func Healthcheck(ctx context.Context, client *http.Client, url string) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("health request: %w", err)
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("health request: status %d", response.StatusCode)
	}
	return nil
}
```

- A distroless image has no shell and no `curl`, so Docker's `HEALTHCHECK` runs the service binary itself with the argument `healthcheck`.
- `context.WithTimeout(ctx, 2*time.Second)` makes a context that is cancelled after two seconds; `defer cancel()` releases it.
- `http.NewRequestWithContext(ctx, http.MethodGet, url, nil)` builds a GET request tied to that context (`nil` is the empty body). `client.Do(request)` sends it.
- `fmt.Errorf("build request: %w", err)` wraps an error: `%w` keeps the original so callers can inspect it.
- `defer func() { _ = response.Body.Close() }()` closes the response body at the end (the body must always be closed; the `_ =` discards the close error on purpose).
- Only status 200 gives `nil` (success); every other status returns an error that names it.

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
