package application_test

import (
	"context"
	"testing"

	"example.com/svc/internal/application"
	"example.com/svc/internal/domain"
)

type fixedSource struct{ info domain.BuildInfo }

func (source fixedSource) Read() domain.BuildInfo { return source.info }

func TestHealthIsOKWhileTheProcessRuns(t *testing.T) {
	service := application.NewService(fixedSource{})

	if got := service.Health(context.Background()); got != domain.StatusOK {
		t.Fatalf("Health() = %q, want %q", got, domain.StatusOK)
	}
}

func TestVersionReturnsWhatTheSourceReports(t *testing.T) {
	want := domain.BuildInfo{Version: "v3", Commit: "abc1234", GoVersion: "go1.25.3"}
	service := application.NewService(fixedSource{info: want})

	if got := service.Version(); got != want {
		t.Fatalf("Version() = %+v, want %+v", got, want)
	}
}
