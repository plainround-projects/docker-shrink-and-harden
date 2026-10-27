# v1: multi-stage. The compiler, the source and the module cache stay in the build stage; only the static binary is
# copied into a slim runtime image. The token is not used yet (this module has no private dependency to fetch);
# v2 adds it back, as a secret.
FROM golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app ./cmd/svc

FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
COPY --from=build /out/app /app
ENTRYPOINT ["/app"]
