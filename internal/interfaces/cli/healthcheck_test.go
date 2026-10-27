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
