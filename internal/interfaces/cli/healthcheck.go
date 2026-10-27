// Package cli holds the service's command-line subcommands.
package cli

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

// Healthcheck requests url and returns nil only for a 200 answer. It is the container's HEALTHCHECK: a distroless
// image has no shell and no curl, so the service binary checks itself.
func Healthcheck(ctx context.Context, client *http.Client, url string) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("health request: %w", err)
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("health request: status %d", response.StatusCode)
	}
	return nil
}
