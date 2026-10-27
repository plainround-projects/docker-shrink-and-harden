# v2: a BuildKit secret mount for the token (it exists only during that one command and is never saved in a layer)
# and cache mounts for the module and compiler caches (they live on the builder, not in the image).
FROM golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af AS build
WORKDIR /src
COPY go.mod ./
RUN --mount=type=secret,id=netrc,target=/root/.netrc \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -v -o /out/app ./cmd/svc

FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
COPY --from=build /out/app /app
ENTRYPOINT ["/app"]
