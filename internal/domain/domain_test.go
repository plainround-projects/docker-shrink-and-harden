package domain_test

import (
	"testing"

	"example.com/svc/internal/domain"
)

func TestBuildInfoStringIsOneLineOfKeyValuePairs(t *testing.T) {
	info := domain.BuildInfo{Version: "v3", Commit: "abc1234", GoVersion: "go1.25.3"}

	want := "version=v3 commit=abc1234 go=go1.25.3"
	if got := info.String(); got != want {
		t.Fatalf("String() = %q, want %q", got, want)
	}
}

func TestStatusOKIsTheWordTheHealthRouteAnswers(t *testing.T) {
	if domain.StatusOK != "ok" {
		t.Fatalf("StatusOK = %q, want ok", domain.StatusOK)
	}
}
