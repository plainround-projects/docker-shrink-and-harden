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
