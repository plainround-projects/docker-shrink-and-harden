// Package buildinfo reports the build's identity: values the Dockerfile stamps with the linker, and the Go version.
package buildinfo

import (
	"runtime"

	"example.com/svc/internal/domain"
)

// Reader implements application.BuildInfoSource.
type Reader struct {
	// Version is set by the Dockerfile with -ldflags "-X main.version=...", then passed in by main.
	Version string
	// Commit is set the same way (-X main.commit=...); empty means the build did not record one.
	Commit string
}

// NewReader returns a Reader for the stamped version and commit.
func NewReader(version, commit string) Reader {
	return Reader{Version: version, Commit: commit}
}

// Read returns the stamped values and the Go version the binary was compiled with. An unstamped commit is "unknown".
func (reader Reader) Read() domain.BuildInfo {
	commit := reader.Commit
	if commit == "" {
		commit = "unknown"
	}
	return domain.BuildInfo{Version: reader.Version, Commit: commit, GoVersion: runtime.Version()}
}
