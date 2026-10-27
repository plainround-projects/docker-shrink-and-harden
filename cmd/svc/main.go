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
