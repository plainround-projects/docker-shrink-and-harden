# Go testing (`go test`, `httptest`, race detector, coverage)

## What it is

Go has testing built in. A file whose name ends in `_test.go` holds tests. A test is a function named `TestSomething(t *testing.T)`. `go test ./...` compiles and runs every test in every package under the current folder and prints `ok` or `FAIL` per package. No extra library is needed. Test files sit next to the code they test.


**Words used in this note**

- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **signal**: A short message the kernel delivers to a process. SIGTERM (number 15) politely asks it to stop; SIGKILL (number 9) cannot be caught and ends it at once.
- **layer**: One step of an image build, stored as its own set of file changes. Unchanged layers are reused from the cache.
- **compiler**: A program that turns source code into machine code that the computer can run directly.
- **image**: A read-only bundle of files and settings from which containers are started.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **process**: A running program. The operating system gives each process a number (its process id, or PID), its own memory and its own list of open files.
- **exit code**: A number a program returns when it ends. 0 means success; any other number means failure. A shell keeps the last one in `$?`.
- **standard output**: Where a program writes its normal text (standard output, stdout) and its error text (standard error, stderr). A terminal shows both. `>` sends output to a file and `|` sends it to another program.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **JSON**: A text format for data. An object is `{"name": "value"}`, a list is `[1, 2]`; values are strings, numbers, `true`, `false` or `null`.
- **thread**: A line of execution inside a process. One process can run several threads, and they share its memory.

## Why this repository uses it

The template wants unit tests with the domain at or near full coverage, table-driven tests next to the code, and an enforced dependency rule. All of it uses plain `go test`.

## Where it appears

| Path | What it tests |
| --- | --- |
| `internal/domain/domain_test.go`, `internal/application/service_test.go` | The types and the service with a fake source. Both at 100% coverage. |
| `internal/infrastructure/*/*_test.go` | Configuration (table-driven), build information, logging. |
| `internal/interfaces/httpapi/httpapi_test.go` | Routes with `httptest`, the request log, a real server started and stopped. |
| `internal/interfaces/cli/healthcheck_test.go` | The health command against a test server. |
| `cmd/svc/main_test.go` | `run` end to end: configuration errors, serving, `SIGTERM`. |
| `internal/architecture_test.go` | The layer rule, checked by reading imports. |
| `scripts/coverage.sh` | Fails if `domain` or `application` fall below 95 percent. |

## How it works underneath

`go test` builds a special test program per package that contains your code plus the tests and runs it. `t.Fatalf` stops the test with a message; `t.Errorf` records a failure and continues. `t.Run(name, func)` makes a **subtest**. A **table-driven test** is a slice of cases (name, input, expected) looped over with `t.Run`; adding a case is adding a row.

`net/http/httptest` provides `NewRecorder` (a fake response writer) and `NewRequestWithContext` so a handler can be called as a plain function, with no network.

`-race` builds the program with the **race detector**, which reports when two goroutines touch the same memory without coordination. `-cover` counts which statements ran. It needs the C compiler (cgo) for `-race`, which the `golang` image includes.

## Walkthrough of this repository's use

### A table-driven test

```go
func TestLoadRejectsBadValuesAndNamesTheSetting(t *testing.T) {
	tests := []struct {
		name   string
		values map[string]string
		want   string
	}{
		{"port not a number", map[string]string{"PORT": "http"}, "PORT"},
		{"port too small", map[string]string{"PORT": "0"}, "PORT"},
		{"port too large", map[string]string{"PORT": "70000"}, "PORT"},
		{"timeout too large", map[string]string{"SHUTDOWN_TIMEOUT_SECONDS": "61"}, "SHUTDOWN_TIMEOUT_SECONDS"},
		{"unknown level", map[string]string{"LOG_LEVEL": "loud"}, "LOG_LEVEL"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := config.Load(environment(test.values))
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("Load() error = %v, want it to mention %s", err, test.want)
			}
		})
	}
}
```

- `tests := []struct{ name string; values map[string]string; want string }{...}` declares an anonymous struct type and a slice of five cases in one expression.
- `for _, test := range tests { t.Run(test.name, func(t *testing.T) {...}) }` runs each case as a named subtest, so a failure says which row broke.
- The test asserts that the error message **names the bad setting** (`strings.Contains(err.Error(), test.want)`).

### Calling a handler without a network

```go
func TestHealthAnswersOKAsPlainText(t *testing.T) {
	recorder := httptest.NewRecorder()

	newHandler(io.Discard).ServeHTTP(recorder, newRequest(http.MethodGet, "/health"))

	if recorder.Code != http.StatusOK || strings.TrimSpace(recorder.Body.String()) != "ok" {
		t.Fatalf("GET /health = %d %q", recorder.Code, recorder.Body.String())
	}
}
```

`httptest.NewRecorder()` collects the response; `ServeHTTP(recorder, request)` runs the handler directly. The test then reads `recorder.Code` and `recorder.Body`.

### A fake through an interface

```go
type fixedSource struct{ info domain.BuildInfo }

func (source fixedSource) Read() domain.BuildInfo { return source.info }
```

`fixedSource` has a `Read()` method, so it satisfies `BuildInfoSource` without any declaration. The service test passes it to `NewService`.

### Testing the real program, including `SIGTERM`

```go
func TestRunServesThenStopsCleanlyOnSIGTERM(t *testing.T) {
	var stderr bytes.Buffer
	port := freePort(t)
	getenv := func(name string) string {
		if name == "PORT" {
			return port
		}
		return ""
	}
	done := make(chan int, 1)
	go func() { done <- run(nil, getenv, &stderr) }()

	deadline := time.Now().Add(3 * time.Second)
	for run([]string{"healthcheck"}, getenv, &bytes.Buffer{}) != 0 {
		if time.Now().After(deadline) {
			t.Fatal("service did not become healthy")
		}
		time.Sleep(50 * time.Millisecond)
	}
	if err := syscall.Kill(syscall.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}

	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("run() = %d after SIGTERM, want 0; stderr %s", code, stderr.String())
		}
	case <-time.After(3 * time.Second):
		t.Fatal("run() did not return after SIGTERM")
	}
}
```

The test starts `run` in a goroutine on a free port, waits (polling the `healthcheck` subcommand) until it answers, sends `SIGTERM` to its own process with `syscall.Kill(syscall.Getpid(), syscall.SIGTERM)`, and asserts `run` returns exit code 0 within three seconds. A channel and `select` with `time.After` give the timeout.

### The dependency rule as a test

The test `TestLayersOnlyImportDownward` walks each layer's folder with `filepath.WalkDir`, parses every non-test file's imports with `go/parser` (`parser.ImportsOnly` reads just the import block), and reports any import that goes upward. A second test makes sure `domain` and `application` import no third-party package.

### Coverage gate

```bash
#!/usr/bin/env bash
# The domain and application packages must keep at least 95 percent statement coverage.
set -euo pipefail

GO_IMAGE="${GO_IMAGE:?run through make test, which sets GO_IMAGE}"
status=0
for package in domain application; do
  output="$(docker run --rm -v "$(pwd)":/src -v shrink-gomod:/go/pkg/mod -v shrink-gobuild:/root/.cache/go-build -w /src "${GO_IMAGE}" go test -cover "./internal/${package}/...")"
  percent="$(echo "${output}" | sed -n 's/.*coverage: \([0-9.]*\)%.*/\1/p')"
  if awk -v p="${percent}" 'BEGIN { exit !(p >= 95) }'; then
    echo "coverage of internal/${package}: ${percent}% (needs 95%)"
  else
    echo "coverage of internal/${package}: ${percent:-none}% is below 95%"
    status=1
  fi
done
exit "${status}"
```

For each of the two inner layers the script runs `go test -cover`, extracts the percentage with `sed`, and compares it with `awk`; the script exits 1 if either is below 95.

### Every test file, whole

Go's testing needs no extra tool. A file named `*_test.go` holds tests; a function named `TestSomething(t *testing.T)` is one test. `t.Fatalf(...)` reports a failure and stops that test; `t.Errorf(...)` reports a failure and carries on; `t.Helper()` marks a function as a helper so failures are reported at the caller's line; `t.Run(name, func...)` runs a **subtest**. A test file whose package ends in `_test` (for example `package domain_test`) can only use what the package exports, the way real callers do. `go test ./...` runs every package.

#### `internal/domain/domain_test.go`

```go
package domain_test

import (
	"testing"

	"example.com/svc/internal/domain"
)

func TestBuildInfoStringIsOneLineOfKeyValuePairs(t *testing.T) {
	info := domain.BuildInfo{Version: "v3", Commit: "abc1234", GoVersion: "go1.25.3"}

	want := "version=v3 commit=abc1234 go=go1.25.3"
	if got := info.String(); got != want {
		t.Fatalf("String() = %q, want %q", got, want)
	}
}

func TestStatusOKIsTheWordTheHealthRouteAnswers(t *testing.T) {
	if domain.StatusOK != "ok" {
		t.Fatalf("StatusOK = %q, want ok", domain.StatusOK)
	}
}
```

Two tests: `BuildInfo.String()` gives `version=v3 commit=abc1234 go=go1.25.3` (the Go version here is just test data), and `StatusOK` is the word `ok`, which the health route answers.

#### `internal/application/service_test.go`

```go
package application_test

import (
	"context"
	"testing"

	"example.com/svc/internal/application"
	"example.com/svc/internal/domain"
)

type fixedSource struct{ info domain.BuildInfo }

func (source fixedSource) Read() domain.BuildInfo { return source.info }

func TestHealthIsOKWhileTheProcessRuns(t *testing.T) {
	service := application.NewService(fixedSource{})

	if got := service.Health(context.Background()); got != domain.StatusOK {
		t.Fatalf("Health() = %q, want %q", got, domain.StatusOK)
	}
}

func TestVersionReturnsWhatTheSourceReports(t *testing.T) {
	want := domain.BuildInfo{Version: "v3", Commit: "abc1234", GoVersion: "go1.25.3"}
	service := application.NewService(fixedSource{info: want})

	if got := service.Version(); got != want {
		t.Fatalf("Version() = %+v, want %+v", got, want)
	}
}
```

`fixedSource` is a **fake**: a tiny type with a `Read()` method that returns whatever it was given, so it satisfies `BuildInfoSource`. The first test checks that `Health` reports `StatusOK`; the second checks that `Version` returns exactly what the source reports. `got != want` compares two structs field by field, which Go allows because every field can be compared. `%+v` prints a struct with its field names.

#### `internal/infrastructure/buildinfo/buildinfo_test.go`

```go
package buildinfo_test

import (
	"runtime"
	"testing"

	"example.com/svc/internal/domain"
	"example.com/svc/internal/infrastructure/buildinfo"
)

func TestReadReturnsTheStampedValuesAndTheGoVersion(t *testing.T) {
	got := buildinfo.NewReader("v3", "0123456789ab").Read()

	want := domain.BuildInfo{Version: "v3", Commit: "0123456789ab", GoVersion: runtime.Version()}
	if got != want {
		t.Fatalf("Read() = %+v, want %+v", got, want)
	}
}

func TestReadReportsAnUnstampedCommitAsUnknown(t *testing.T) {
	if got := buildinfo.NewReader("dev", "").Read().Commit; got != "unknown" {
		t.Fatalf("Commit = %q, want unknown", got)
	}
}
```

The reader returns the stamped version and commit plus the running toolchain's version (`runtime.Version()`), and reports an empty commit as `unknown`.

#### `internal/infrastructure/logging/logging_test.go`

```go
package logging_test

import (
	"bytes"
	"log/slog"
	"strings"
	"testing"

	"example.com/svc/internal/infrastructure/logging"
)

func TestNewWritesKeyValueLinesAtOrAboveTheLevel(t *testing.T) {
	var out bytes.Buffer
	logger := logging.New(&out, slog.LevelWarn)

	logger.Info("hidden")
	logger.Warn("shown", "port", 8080)

	text := out.String()
	if strings.Contains(text, "hidden") || !strings.Contains(text, "msg=shown") || !strings.Contains(text, "port=8080") {
		t.Fatalf("log output = %q", text)
	}
}
```

A `bytes.Buffer` stands in for standard error. With the level at `Warn`, an `Info` event must not appear and a `Warn` event must, as `msg=shown` and `port=8080` in the text. This proves both the level filter and the `key=value` format.

#### `internal/infrastructure/config/config_test.go`

```go
package config_test

import (
	"log/slog"
	"strings"
	"testing"
	"time"

	"example.com/svc/internal/infrastructure/config"
)

func environment(values map[string]string) func(string) string {
	return func(name string) string { return values[name] }
}

func TestLoadAppliesDefaults(t *testing.T) {
	got, err := config.Load(environment(nil))
	if err != nil {
		t.Fatal(err)
	}

	if got.Addr != ":8080" || got.LogLevel != slog.LevelInfo || got.ShutdownTimeout != 8*time.Second {
		t.Fatalf("Load() = %+v", got)
	}
}

func TestLoadReadsEveryValue(t *testing.T) {
	got, err := config.Load(environment(map[string]string{"PORT": "9000", "LOG_LEVEL": "debug", "SHUTDOWN_TIMEOUT_SECONDS": "3"}))
	if err != nil {
		t.Fatal(err)
	}

	if got.Addr != ":9000" || got.LogLevel != slog.LevelDebug || got.ShutdownTimeout != 3*time.Second {
		t.Fatalf("Load() = %+v", got)
	}
}

func TestLoadRejectsBadValuesAndNamesTheSetting(t *testing.T) {
	tests := []struct {
		name   string
		values map[string]string
		want   string
	}{
		{"port not a number", map[string]string{"PORT": "http"}, "PORT"},
		{"port too small", map[string]string{"PORT": "0"}, "PORT"},
		{"port too large", map[string]string{"PORT": "70000"}, "PORT"},
		{"timeout too large", map[string]string{"SHUTDOWN_TIMEOUT_SECONDS": "61"}, "SHUTDOWN_TIMEOUT_SECONDS"},
		{"unknown level", map[string]string{"LOG_LEVEL": "loud"}, "LOG_LEVEL"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := config.Load(environment(test.values))
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("Load() error = %v, want it to mention %s", err, test.want)
			}
		})
	}
}
```

- `environment(values)` returns a function that looks names up in a map; with `nil` every lookup gives the empty string, which means "not set". This is why `Load` takes a function instead of calling `os.Getenv`.
- `TestLoadAppliesDefaults`: port 8080, level info, timeout 8 seconds.
- `TestLoadReadsEveryValue`: `PORT=9000`, `LOG_LEVEL=debug` and `SHUTDOWN_TIMEOUT_SECONDS=3` are all honored.
- `TestLoadRejectsBadValuesAndNamesTheSetting` is a **table-driven test**: a slice of structs, one per case, run in a loop with `t.Run(test.name, ...)` so each case is reported separately. Five bad inputs (a word as port, port 0, port 70000, timeout 61, level `loud`) must each fail with a message that mentions the setting's name.

#### `internal/interfaces/cli/healthcheck_test.go`

```go
package cli_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"example.com/svc/internal/interfaces/cli"
)

func TestHealthcheckSucceedsOnlyOnA200Answer(t *testing.T) {
	tests := []struct {
		name    string
		status  int
		wantErr bool
	}{
		{"healthy", http.StatusOK, false},
		{"unavailable", http.StatusServiceUnavailable, true},
		{"no content", http.StatusNoContent, true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(test.status) }))
			defer server.Close()

			err := cli.Healthcheck(context.Background(), server.Client(), server.URL)

			if (err != nil) != test.wantErr {
				t.Fatalf("Healthcheck() error = %v, wantErr %v", err, test.wantErr)
			}
		})
	}
}

func TestHealthcheckFailsWhenNothingListens(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	url := server.URL
	server.Close()

	if err := cli.Healthcheck(context.Background(), http.DefaultClient, url); err == nil {
		t.Fatal("Healthcheck() against a closed server = nil, want an error")
	}
}

func TestHealthcheckRejectsAMalformedURL(t *testing.T) {
	if err := cli.Healthcheck(context.Background(), http.DefaultClient, "://bad"); err == nil {
		t.Fatal("Healthcheck() with a malformed URL = nil, want an error")
	}
}
```

`httptest.NewServer` starts a real HTTP server on a free local port, answering with whatever status the case asks for. A 200 must give no error; 503 and 204 must both give an error (only 200 counts as healthy). After `server.Close()` the address no longer listens, and the check must fail. A URL like `://bad` cannot even be parsed, and must fail too. `(err != nil) != test.wantErr` is true when the outcome differs from the expectation.

#### `internal/interfaces/httpapi/httpapi_test.go`

```go
package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"example.com/svc/internal/application"
	"example.com/svc/internal/domain"
	"example.com/svc/internal/interfaces/httpapi"
)

type fixedSource struct{}

func (fixedSource) Read() domain.BuildInfo {
	return domain.BuildInfo{Version: "v3", Commit: "abc1234", GoVersion: "go1.25"}
}

func newRequest(method, path string) *http.Request {
	return httptest.NewRequestWithContext(context.Background(), method, path, nil)
}

func listen() (net.Listener, error) {
	return (&net.ListenConfig{}).Listen(context.Background(), "tcp", "127.0.0.1:0")
}

func newHandler(logs io.Writer) http.Handler {
	logger := slog.New(slog.NewTextHandler(logs, nil))
	return httpapi.NewHandler(application.NewService(fixedSource{}), logger)
}

func TestHealthAnswersOKAsPlainText(t *testing.T) {
	recorder := httptest.NewRecorder()

	newHandler(io.Discard).ServeHTTP(recorder, newRequest(http.MethodGet, "/health"))

	if recorder.Code != http.StatusOK || strings.TrimSpace(recorder.Body.String()) != "ok" {
		t.Fatalf("GET /health = %d %q", recorder.Code, recorder.Body.String())
	}
}

func TestVersionAnswersTheBuildAsJSON(t *testing.T) {
	recorder := httptest.NewRecorder()

	newHandler(io.Discard).ServeHTTP(recorder, newRequest(http.MethodGet, "/version"))

	var got domain.BuildInfo
	if err := json.Unmarshal(recorder.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Version != "v3" || recorder.Header().Get("Content-Type") != "application/json" {
		t.Fatalf("GET /version = %+v, content type %q", got, recorder.Header().Get("Content-Type"))
	}
}

func TestUnknownRoutesAndWrongMethodsAreRejected(t *testing.T) {
	tests := []struct {
		method, path string
		want         int
	}{
		{http.MethodGet, "/nope", http.StatusNotFound},
		{http.MethodPost, "/health", http.StatusMethodNotAllowed},
	}
	for _, test := range tests {
		recorder := httptest.NewRecorder()
		newHandler(io.Discard).ServeHTTP(recorder, newRequest(test.method, test.path))
		if recorder.Code != test.want {
			t.Errorf("%s %s = %d, want %d", test.method, test.path, recorder.Code, test.want)
		}
	}
}

func TestEveryRequestIsLoggedWithMethodPathAndStatus(t *testing.T) {
	var logs bytes.Buffer

	newHandler(&logs).ServeHTTP(httptest.NewRecorder(), newRequest(http.MethodGet, "/health"))

	for _, want := range []string{"msg=request", "method=GET", "path=/health", "status=200"} {
		if !strings.Contains(logs.String(), want) {
			t.Errorf("log %q does not contain %q", logs.String(), want)
		}
	}
}

func TestServeStopsCleanlyWhenTheContextIsCancelled(t *testing.T) {
	listener, err := listen()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- httpapi.Serve(ctx, listener, newHandler(io.Discard), time.Second, slog.New(slog.NewTextHandler(io.Discard, nil)))
	}()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://"+listener.Addr().String()+"/health", nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	_ = response.Body.Close()
	cancel()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Serve() = %v, want nil after a clean shutdown", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("Serve() did not return after the context was cancelled")
	}
}

func TestServeReportsAListenerThatFails(t *testing.T) {
	listener, err := listen()
	if err != nil {
		t.Fatal(err)
	}
	_ = listener.Close()

	err = httpapi.Serve(context.Background(), listener, newHandler(io.Discard), time.Second, slog.New(slog.NewTextHandler(io.Discard, nil)))

	if err == nil {
		t.Fatal("Serve() on a closed listener = nil, want an error")
	}
}

func TestAPanicInAHandlerIsAnInternalErrorNotACrash(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&logs, nil))
	service := application.NewService(panickingSource{})
	recorder := httptest.NewRecorder()

	httpapi.NewHandler(service, logger).ServeHTTP(recorder, newRequest(http.MethodGet, "/version"))

	if recorder.Code != http.StatusInternalServerError || !strings.Contains(logs.String(), "panic in handler") {
		t.Fatalf("status %d, log %q", recorder.Code, logs.String())
	}
}

type panickingSource struct{}

func (panickingSource) Read() domain.BuildInfo { panic("boom") }
```

- The helpers: `fixedSource` returns a fixed build; `newRequest` builds a request without a network; `listen` opens a port on `127.0.0.1:0` (port 0 means "any free port"); `newHandler(logs)` builds the real handler around a service and a logger that writes into `logs`.
- `httptest.NewRecorder()` is a fake response writer that records the status, headers and body. Calling `handler.ServeHTTP(recorder, request)` runs a handler without a network.
- `/health` answers 200 and the text `ok`. `/version` answers JSON that decodes (`json.Unmarshal`) into a `BuildInfo` with version `v3`, with content type `application/json`.
- An unknown path gives 404 and a POST to `/health` gives 405 (method not allowed).
- Every request is logged with `msg=request method=GET path=/health status=200`.
- `TestServeStopsCleanlyWhenTheContextIsCancelled`: `Serve` runs in a goroutine (`go func() {...}()`, a lightweight thread); the test makes one real request, calls `cancel()`, and expects `Serve` to return `nil` within three seconds. The `done` channel (`make(chan error, 1)`) carries the result between goroutines; `select` waits for the result or a timeout, whichever comes first.
- `TestServeReportsAListenerThatFails`: serving on a closed listener must return an error.
- `TestAPanicInAHandlerIsAnInternalErrorNotACrash`: `panickingSource.Read` calls `panic("boom")`. The handler's recover middleware must turn it into a 500 and log `panic in handler` instead of crashing the process.

#### `internal/architecture_test.go`

```go
// Package internal_test enforces the dependency rule: domain imports nothing of ours; application imports domain;
// infrastructure and interfaces import the layers below; nothing imports interfaces.
package internal_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strings"
	"testing"
)

const module = "example.com/svc/internal/"

// allowed lists, for each layer, the layers its non-test code may import.
var allowed = map[string][]string{
	"domain":         {},
	"application":    {"domain"},
	"infrastructure": {"domain", "application"},
	"interfaces":     {"domain", "application", "infrastructure"},
}

func TestLayersOnlyImportDownward(t *testing.T) {
	for layer, permitted := range allowed {
		err := filepath.WalkDir(layer, func(path string, entry fs.DirEntry, err error) error {
			if err != nil || entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
				return err
			}
			file, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
			if err != nil {
				return err
			}
			for _, spec := range file.Imports {
				target := strings.Trim(spec.Path.Value, `"`)
				if !strings.HasPrefix(target, module) {
					continue
				}
				imported := strings.SplitN(strings.TrimPrefix(target, module), "/", 2)[0]
				if imported != layer && !contains(permitted, imported) {
					t.Errorf("%s (layer %s) imports %s: the layer %q is not allowed", path, layer, target, imported)
				}
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func TestDomainAndApplicationUseOnlyTheStandardLibraryAndEachOther(t *testing.T) {
	for _, layer := range []string{"domain", "application"} {
		_ = filepath.WalkDir(layer, func(path string, entry fs.DirEntry, err error) error {
			if err != nil || entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
				return err
			}
			file, _ := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
			for _, spec := range file.Imports {
				target := strings.Trim(spec.Path.Value, `"`)
				if strings.Contains(strings.SplitN(target, "/", 2)[0], ".") && !strings.HasPrefix(target, module) {
					t.Errorf("%s imports third-party package %s", path, target)
				}
			}
			return nil
		})
	}
}

func contains(list []string, item string) bool {
	for _, candidate := range list {
		if candidate == item {
			return true
		}
	}
	return false
}
```

- `allowed` is a map from layer to the layers it may import. The first test walks every non-test `.go` file of each layer (`filepath.WalkDir`), parses only its import lines (`parser.ImportsOnly`), and fails with the file name if a layer imports a layer it is not allowed to (domain imports nothing of ours; application only domain; infrastructure domain and application; interfaces all three).
- The second test checks that `domain` and `application` import no third-party package: an import path whose first element contains a dot (like `github.com/...`) and does not start with this module's path is third-party.
- `contains` is a small helper that tells whether a slice has an item. It is the Go equivalent of an import-linter contract.

#### `cmd/svc/main_test.go`

```go
package main

import (
	"bytes"
	"context"
	"net"
	"strings"
	"syscall"
	"testing"
	"time"
)

func freePort(t *testing.T) string {
	t.Helper()
	listener, err := (&net.ListenConfig{}).Listen(context.Background(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listener.Close() }()
	_, port, _ := net.SplitHostPort(listener.Addr().String())
	return port
}

func TestRunRefusesToStartWithABadConfiguration(t *testing.T) {
	var stderr bytes.Buffer

	code := run(nil, func(name string) string {
		if name == "PORT" {
			return "not-a-port"
		}
		return ""
	}, &stderr)

	if code != 2 || !strings.Contains(stderr.String(), "PORT") {
		t.Fatalf("run() = %d, stderr %q; want 2 mentioning PORT", code, stderr.String())
	}
}

func TestHealthcheckSubcommandFailsWhenNoServiceListens(t *testing.T) {
	var stderr bytes.Buffer
	port := freePort(t)

	code := run([]string{"healthcheck"}, func(name string) string {
		if name == "PORT" {
			return port
		}
		return ""
	}, &stderr)

	if code != 1 {
		t.Fatalf("run(healthcheck) = %d, want 1", code)
	}
}

func TestRunServesThenStopsCleanlyOnSIGTERM(t *testing.T) {
	var stderr bytes.Buffer
	port := freePort(t)
	getenv := func(name string) string {
		if name == "PORT" {
			return port
		}
		return ""
	}
	done := make(chan int, 1)
	go func() { done <- run(nil, getenv, &stderr) }()

	deadline := time.Now().Add(3 * time.Second)
	for run([]string{"healthcheck"}, getenv, &bytes.Buffer{}) != 0 {
		if time.Now().After(deadline) {
			t.Fatal("service did not become healthy")
		}
		time.Sleep(50 * time.Millisecond)
	}
	if err := syscall.Kill(syscall.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}

	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("run() = %d after SIGTERM, want 0; stderr %s", code, stderr.String())
		}
	case <-time.After(3 * time.Second):
		t.Fatal("run() did not return after SIGTERM")
	}
}

func TestRunReportsAPortThatIsAlreadyInUse(t *testing.T) {
	var stderr bytes.Buffer
	taken, err := (&net.ListenConfig{}).Listen(context.Background(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = taken.Close() }()
	_, port, _ := net.SplitHostPort(taken.Addr().String())

	code := run(nil, func(name string) string {
		if name == "PORT" {
			return port
		}
		return ""
	}, &stderr)

	if code != 1 {
		t.Fatalf("run() = %d, want 1", code)
	}
}
```

- `freePort` opens port 0, reads the port the system picked, closes the listener and returns the number, so tests do not clash with anything running on 8080.
- A bad `PORT` makes `run` return 2 and print a message that mentions `PORT`.
- `healthcheck` with nothing listening returns 1.
- `TestRunServesThenStopsCleanlyOnSIGTERM` starts `run` in a goroutine, polls the health subcommand until the service answers (up to three seconds), sends the test process itself a SIGTERM (`syscall.Kill(syscall.Getpid(), syscall.SIGTERM)`), and expects `run` to return 0: the graceful-shutdown claim of the lesson, tested.
- A port that is already in use makes `run` return 1.

## Try it yourself

1. Run everything: `make test`. Expected: nine `ok` lines, then `coverage of internal/domain: 100.0%` and `internal/application: 100.0%`.
2. Run one package verbosely: `docker run --rm -v "$PWD:/src" -w /src golang:1.26-bookworm go test -v ./internal/infrastructure/config/`. Expected: one `=== RUN` line for `TestLoadRejectsBadValuesAndNamesTheSetting` and one for each of its five subtests (`.../port_not_a_number`, `.../port_too_small`, `.../port_too_large`, `.../timeout_too_large`, `.../unknown_level`), each ending in `PASS`.
3. Break the rule: in a copy add `import "example.com/svc/internal/interfaces/httpapi"` to `internal/domain/domain.go` and run `go test ./internal/`. Expected: `TestLayersOnlyImportDownward` fails with a message naming the file and the import.
4. See the race detector work: `make test` runs with `-race`; no output about races means none were found.

## Mistakes people make

- Tests that depend on timing without a timeout (a hang blocks CI). Here every wait has a deadline.
- Sharing state between subtests.
- Chasing coverage numbers on glue code. The gate applies to the inner layers only.
- Using real ports with fixed numbers; the tests ask the system for a free one (`127.0.0.1:0`).

## Check yourself

1. What makes a function a test? *Its name starts with `Test` in a `_test.go` file and it takes `*testing.T`.*
2. What is a table-driven test? *A slice of cases run in a loop as subtests.*
3. What does `httptest.NewRecorder` replace? *The network connection: a handler writes into the recorder.*
4. What does `-race` detect? *Unsynchronized access to shared memory by goroutines.*
5. Why port `:0`? *The system picks a free port, so tests never clash.*

## Further reading

- Package `testing`: <https://pkg.go.dev/testing@go1.26>
- Table-driven tests: <https://go.dev/wiki/TableDrivenTests>
- `httptest`: <https://pkg.go.dev/net/http/httptest@go1.26>
- The race detector: <https://go.dev/doc/articles/race_detector>
- Coverage: <https://go.dev/blog/cover>
