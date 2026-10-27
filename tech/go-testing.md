# Go testing (`go test`, `httptest`, race detector, coverage)

## What it is

Go has testing built in. A file whose name ends in `_test.go` holds tests. A test is a function named `TestSomething(t *testing.T)`. `go test ./...` compiles and runs every test in every package under the current folder and prints `ok` or `FAIL` per package. No extra library is needed. Test files sit next to the code they test.

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

## Try it yourself

1. Run everything: `make test`. Expected: nine `ok` lines, then `coverage of internal/domain: 100.0%` and `internal/application: 100.0%`.
2. Run one package verbosely: `docker run --rm -v "$PWD:/src" -w /src golang:1.26-bookworm go test -v ./internal/infrastructure/config/`. Expected: `=== RUN TestLoadRejectsBadValuesAndNamesTheSetting/port_not_a_number` and so on, each `PASS`.
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
