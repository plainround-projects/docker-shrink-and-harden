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
