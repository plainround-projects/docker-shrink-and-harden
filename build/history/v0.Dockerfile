# v0: the starting point, as the lesson gives it. One stage on the full SDK image, and the private-package token
# passed as a build argument, which is the mistake: the value is stored in the image history for ever.
# Kept for the measurements and the history check; it is deliberately not linted.
FROM golang:1.26-bookworm@sha256:632dff7351799a5a9954a48dc06670ade72ee44e8c351cdc0e5a57af2fea21af
ARG PKG_TOKEN
WORKDIR /src
COPY . .
RUN echo "machine packages.internal.example login ci password ${PKG_TOKEN}" > /root/.netrc && go mod download && go build -o /app ./cmd/svc
ENTRYPOINT ["/app"]
