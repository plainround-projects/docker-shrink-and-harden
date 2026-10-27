# Measurements

Captured by `make measure` on 2026-10-27 (arm64, Docker 24.0.6, buildx v0.11.2-desktop.5, scanner aquasec/trivy:0.58.0). Times are wall-clock seconds on one laptop and differ on yours; the order of the rows and the ratios are what matter. Cold: no layer cache and empty cache mounts on the project's own builder, base images already pulled. Warm: one line of `cmd/svc/main.go` changed, then a rebuild.

| Version | What changed | Image size | Cold build | Warm build (1-line change) | Scanner: critical/high | Token lines in `docker history` |
| --- | --- | --- | --- | --- | --- | --- |
| v0 | one stage on the full SDK image, token as a build argument | 937 MB | 24.75 s | 26.96 s | 7/290 | 2 |
| v1 | multi-stage, debian slim runtime | 106 MB | 26.38 s | 21.11 s | 1/56 | 0 |
| v2 | secret mount for the token, cache mounts | 106 MB | 29.88 s | 7.83 s | 1/56 | 0 |
| v3 | distroless static, non-root, bases pinned by digest | 8 MB | 12.09 s | 7.57 s | 0/0 | 0 |
| v4 | v3 plus SBOM and provenance | 8 MB | 18.34 s | 6.89 s | 0/0 | 0 |
