// Package domain holds the service's vocabulary. It imports nothing outside the standard library.
package domain

import "fmt"

// Status is the answer to a health check.
type Status string

// StatusOK means the process is serving.
const StatusOK Status = "ok"

// BuildInfo identifies the binary: which version and commit it was built from and with which Go toolchain.
// It is what lets an operator match a running container to an image and to the packages listed in its SBOM.
type BuildInfo struct {
	Version   string `json:"version"`
	Commit    string `json:"commit"`
	GoVersion string `json:"goVersion"`
}

// String renders the build information on one line, for logs.
func (info BuildInfo) String() string {
	return fmt.Sprintf("version=%s commit=%s go=%s", info.Version, info.Commit, info.GoVersion)
}
