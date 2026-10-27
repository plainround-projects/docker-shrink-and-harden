// Package application holds the use cases and the ports they need. It depends on the domain only.
package application

import (
	"context"

	"example.com/svc/internal/domain"
)

// BuildInfoSource tells the service which binary it is.
type BuildInfoSource interface {
	Read() domain.BuildInfo
}

// Service answers the two questions an orchestrator and an operator ask: are you up, and which build are you.
type Service struct {
	source BuildInfoSource
}

// NewService returns a Service that reads its build information from source.
func NewService(source BuildInfoSource) *Service {
	return &Service{source: source}
}

// Health reports whether the service is serving. The service has no dependencies, so a running process is healthy;
// the context is part of the signature so a dependency check can be added without changing callers.
func (service *Service) Health(_ context.Context) domain.Status {
	return domain.StatusOK
}

// Version returns the identity of the running binary.
func (service *Service) Version() domain.BuildInfo {
	return service.source.Read()
}
