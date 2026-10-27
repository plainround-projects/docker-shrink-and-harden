package buildinfo_test

import (
	"runtime"
	"testing"

	"example.com/svc/internal/domain"
	"example.com/svc/internal/infrastructure/buildinfo"
)

func TestReadReturnsTheStampedValuesAndTheGoVersion(t *testing.T) {
	got := buildinfo.NewReader("v3", "0123456789ab").Read()

	want := domain.BuildInfo{Version: "v3", Commit: "0123456789ab", GoVersion: runtime.Version()}
	if got != want {
		t.Fatalf("Read() = %+v, want %+v", got, want)
	}
}

func TestReadReportsAnUnstampedCommitAsUnknown(t *testing.T) {
	if got := buildinfo.NewReader("dev", "").Read().Commit; got != "unknown" {
		t.Fatalf("Commit = %q, want unknown", got)
	}
}
