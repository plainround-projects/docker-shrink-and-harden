// Package config reads the service's settings from the environment and validates them once, at start.
package config

import (
	"fmt"
	"log/slog"
	"strconv"
	"time"
)

// Config is everything the service reads from its environment.
type Config struct {
	Addr            string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
}

// Load reads PORT (default 8080), LOG_LEVEL (default info) and SHUTDOWN_TIMEOUT_SECONDS (default 8) through getenv.
func Load(getenv func(string) string) (Config, error) {
	port, err := integer(getenv, "PORT", 8080, 1, 65535)
	if err != nil {
		return Config{}, err
	}
	seconds, err := integer(getenv, "SHUTDOWN_TIMEOUT_SECONDS", 8, 1, 60)
	if err != nil {
		return Config{}, err
	}
	level := slog.LevelInfo
	if raw := getenv("LOG_LEVEL"); raw != "" {
		if err := level.UnmarshalText([]byte(raw)); err != nil {
			return Config{}, fmt.Errorf("LOG_LEVEL must be debug, info, warn or error, got %q", raw)
		}
	}
	return Config{
		Addr:            ":" + strconv.Itoa(port),
		LogLevel:        level,
		ShutdownTimeout: time.Duration(seconds) * time.Second,
	}, nil
}

func integer(getenv func(string) string, name string, fallback, minimum, maximum int) (int, error) {
	raw := getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be an integer, got %q", name, raw)
	}
	if value < minimum || value > maximum {
		return 0, fmt.Errorf("%s must be between %d and %d, got %d", name, minimum, maximum, value)
	}
	return value, nil
}
