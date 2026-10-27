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
