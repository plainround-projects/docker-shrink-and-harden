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
