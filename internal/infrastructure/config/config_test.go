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
