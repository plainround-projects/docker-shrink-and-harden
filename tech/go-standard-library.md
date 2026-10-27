# The Go standard library: net/http, log/slog, context, os/signal

## What it is

Go ships with a large **standard library**: packages that come with the compiler and need no download. This service uses four of them to be a complete HTTP server:

- `net/http`: an HTTP server and client.
- `log/slog`: structured logging.
- `context`: carrying cancellation and deadlines.
- `os/signal` (with `syscall`): receiving operating-system signals.
- Also `encoding/json`, `runtime/debug`-style build data (`runtime`), `time` and `net`.

## Why this repository uses it

The lesson's service is a few lines of `net/http`. Using only the standard library means **no third-party code in the image**: the binary is small, the scanner has fewer packages to report, and `go mod download` has nothing to fetch. It also shows what a "production-grade" Go service needs without frameworks: timeouts, graceful shutdown, request logs.

## Where it appears

| Path | What it uses |
| --- | --- |
| `internal/interfaces/httpapi/handler.go` | `net/http` routing and middleware, `encoding/json`, `log/slog`. |
| `internal/interfaces/httpapi/server.go` | `http.Server` with timeouts, `context`, graceful `Shutdown`. |
| `internal/interfaces/cli/healthcheck.go` | An HTTP client with a `context` deadline. |
| `cmd/svc/main.go` | `os/signal.NotifyContext` for `SIGTERM` and `SIGINT`. |
| `internal/infrastructure/logging/logging.go` | `slog.NewTextHandler`. |
| `internal/infrastructure/buildinfo/buildinfo.go` | `runtime.Version()`. |

## How it works underneath

**HTTP server.** `net/http` listens on a TCP port and starts a goroutine per connection. It parses each request and calls a **handler**: any value with a method `ServeHTTP(w ResponseWriter, r *Request)`. A **ServeMux** is a router that picks a handler from the method and path. Since Go 1.22 a pattern can include the method: `"GET /health"`.

**Middleware** is a function that takes a handler and returns a new handler that does something before or after calling it (logging, recovering from a panic).

**Signals.** The operating system tells a process "please stop" with `SIGTERM`. `signal.NotifyContext` returns a `context` that is cancelled when one arrives, so the rest of the program only has to watch the context.

**Graceful shutdown.** `server.Shutdown(ctx)` stops accepting new connections, waits for requests in flight to finish (up to the context's deadline) and returns. That is how `docker stop` ends the service cleanly.

**Structured logging.** `slog` writes `key=value` pairs. The text handler produces lines like `time=... level=INFO msg=request method=GET path=/health status=200 ms=0.1`.

## Walkthrough of this repository's use

### Routes and middleware

```go
func NewHandler(service *application.Service, logger *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		_, _ = fmt.Fprintln(w, service.Health(r.Context()))
	})
	mux.HandleFunc("GET /version", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(service.Version()); err != nil {
			logger.Error("write version", "error", err)
		}
	})
	return recoverPanics(logRequests(mux, logger), logger)
```

- `http.NewServeMux()` makes the router. `mux.HandleFunc("GET /health", ...)` registers a function for GET on that path; another method gets `405 Method Not Allowed` automatically, and unknown paths get `404`.
- `fmt.Fprintln(w, service.Health(r.Context()))` writes `ok` and a newline to the response. `r.Context()` is the request's context, cancelled if the client disconnects.
- `json.NewEncoder(w).Encode(value)` writes the value as JSON. The `Content-Type` header is set first.
- The last line wraps the router: `recoverPanics(logRequests(mux, logger), logger)`. A request passes through recovery, then logging, then the router.

```go
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (recorder *statusRecorder) WriteHeader(status int) {
	recorder.status = status
	recorder.ResponseWriter.WriteHeader(status)
}

func logRequests(next http.Handler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)
		logger.Info("request", "method", r.Method, "path", r.URL.Path, "status", recorder.status,
			"ms", float64(time.Since(started).Microseconds())/1000)
	})
```

`statusRecorder` embeds `http.ResponseWriter` (it gains all its methods) and overrides `WriteHeader` to remember the status code. That is how the log line knows the status. `time.Since(started)` measures the duration.

```go
func recoverPanics(next http.Handler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.Error("panic in handler", "panic", recovered, "path", r.URL.Path)
				http.Error(w, "internal error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
```

`defer` schedules a function to run when the surrounding function returns. `recover()` catches a **panic** (a crash in a handler) so one bad request cannot kill the server; it logs and answers `500`.

### The server and graceful shutdown

```go
func Serve(ctx context.Context, listener net.Listener, handler http.Handler, shutdownTimeout time.Duration, logger *slog.Logger) error {
	server := &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	failed := make(chan error, 1)
	go func() {
		logger.Info("listening", "addr", listener.Addr().String())
		if err := server.Serve(listener); !errors.Is(err, http.ErrServerClosed) {
			failed <- fmt.Errorf("serve: %w", err)
		}
		close(failed)
	}()

	select {
	case err := <-failed:
		return err
	case <-ctx.Done():
	}
	logger.Info("shutting down", "timeout", shutdownTimeout.String())
	shutdownContext, cancel := context.WithTimeout(context.WithoutCancel(ctx), shutdownTimeout)
	defer cancel()
	if err := server.Shutdown(shutdownContext); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	return <-failed
```

- The `http.Server` sets four timeouts. `ReadHeaderTimeout` limits how long a client may take to send headers (it defends against slow-sending attackers); the others limit the whole read, the write and idle connections.
- `failed := make(chan error, 1)` is a **channel**, a pipe between goroutines; the capacity 1 means a send does not block. `go func() {...}()` starts a goroutine that runs `server.Serve(listener)`, which blocks until the server closes.
- `errors.Is(err, http.ErrServerClosed)` recognizes the normal result of `Shutdown`. Any other error is wrapped with `fmt.Errorf("serve: %w", err)`; `%w` keeps the original error inside so callers can still test for it.
- `select { case err := <-failed: ... case <-ctx.Done(): }` waits for whichever happens first: the server failing, or the context being cancelled by a signal.
- `context.WithoutCancel(ctx)` creates a new context that keeps values but is not cancelled; then `WithTimeout` gives the shutdown at most `shutdownTimeout` (8 seconds by default, inside Docker's 10).

### Signals

```go
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
```

`signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)` returns a context cancelled on either signal and a `stop` function that releases the handler (`defer stop()`). If the first argument is `healthcheck`, the same binary runs as the container's health command instead of serving.

## Try it yourself

1. Run the HTTP tests: `make test`. Expected: `ok example.com/svc/internal/interfaces/httpapi ... coverage: 94.4% of statements`.
2. Call the running service: `make run` then `curl -si localhost:8089/health`. Expected: `HTTP/1.1 200 OK` and body `ok`.
3. Wrong method: `curl -si -X POST localhost:8089/health`. Expected: `405 Method Not Allowed`.
4. Watch graceful shutdown: `docker logs <container>` after `docker stop`. Expected: lines `shutting down timeout=8s` then `stopped`, and exit code 0.

## Mistakes people make

- Using `http.ListenAndServe` with no timeouts; a slow client can hold a connection for ever.
- Calling `os.Exit` inside handlers or goroutines, skipping `defer` and shutdown.
- Ignoring `Shutdown`'s error.
- Reading the request body without limits.

## Check yourself

1. What is a handler in `net/http`? *A value with a `ServeHTTP(w, r)` method.*
2. What does `Shutdown` do? *Stops accepting connections and waits for requests in flight, up to the context's deadline.*
3. What does `defer` do? *Runs a function when the surrounding function returns.*
4. Why a context from `signal.NotifyContext`? *The program watches one context instead of handling signals in many places.*
5. What does `%w` do in `fmt.Errorf`? *Wraps an error so `errors.Is` and `errors.As` can still find it.*

## Further reading

- `net/http`: <https://pkg.go.dev/net/http@go1.26>
- Routing patterns (Go 1.22): <https://go.dev/blog/routing-enhancements>
- `log/slog`: <https://pkg.go.dev/log/slog@go1.26>
- `context`: <https://pkg.go.dev/context@go1.26>
- `os/signal`: <https://pkg.go.dev/os/signal@go1.26>
