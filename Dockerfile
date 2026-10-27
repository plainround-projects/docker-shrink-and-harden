# The service image (v3 in the lesson's table, and v4 when built with an SBOM and provenance: `make sbom`).
# Compile in a build stage on the SDK image; ship only a static binary on a distroless base that has no shell, no
# package manager and runs as UID 65532. Both bases are pinned by digest; the tag stays beside the digest for people.
FROM golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af AS build
ARG VERSION=dev
ARG COMMIT=unknown
WORKDIR /src
COPY go.mod ./
# The private-package token arrives as a build secret and exists only for this one command. `required=false` keeps
# the build working where there is no private package server to authenticate to (CI, a fresh clone).
RUN --mount=type=secret,id=netrc,target=/root/.netrc,required=false \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -v -trimpath -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" -o /out/app ./cmd/svc

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
# A distroless image has no shell or curl, so the binary checks itself.
HEALTHCHECK --interval=15s --timeout=3s --start-period=3s --retries=3 CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
