# Docker registry, tags and digests

## What it is

A **registry** is a server that stores and serves container images. Docker Hub is the best known. `docker push` uploads an image to a registry; `docker pull` downloads it. An image reference looks like `host:port/name:tag` or `host:port/name@sha256:digest`. A **tag** is a movable label such as `v3`. A **digest** is the SHA-256 fingerprint of the image's manifest (its list of layers), so it names exactly one set of bytes.

This repository runs the official `registry:2` image as a local registry on `127.0.0.1:5057`, so pushing, pulling and inspecting digests needs no account anywhere.


**Words used in this note**

- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **JSON**: A text format for data. An object is `{"name": "value"}`, a list is `[1, 2]`; values are strings, numbers, `true`, `false` or `null`.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **TLS**: The encryption used by HTTPS. A certificate is a file that proves who a server is; an authority that the client trusts has signed it.
- **API**: The set of requests one program offers to other programs, for example 'GET /health returns ok'.

## Why this repository uses it

Step 5 of the lesson: "pin and push by digest ... retagging `latest` to a different image does not change what your deploy command runs". You can only demonstrate that with a registry.

## Where it appears

| Path | What it does |
| --- | --- |
| `docker-compose.yml` (service `registry`) | Runs the registry with a volume, a health check and resource limits. |
| `scripts/deploy.sh` | Pushes `svc:v3`, reads the digest, deploys by digest. |
| `tests/e2e/05_digest_pinning.sh` | Pushes, moves the tag, shows the digest deploy is unchanged. |
| `.env.example` | `REGISTRY_PORT=5057`. |

## How it works underneath

Pushing uploads each layer by its digest (skipping ones the registry already has), then uploads the **manifest**, a small JSON document listing the layers and config. The registry answers with the manifest's digest. A tag is a pointer from a name to a manifest digest; pushing another image under the same tag moves the pointer, and the old manifest stays stored and still reachable by digest. Docker treats `localhost` registries as allowed over plain HTTP, so no certificate is needed.

Port 5000 is the usual registry port, but macOS uses it for AirPlay Receiver, and another process held 5001 on the build machine, so the repository publishes on 5057 (configurable).

## Walkthrough of this repository's use

```yaml
  registry:
    image: registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373
    ports:
      # Loopback only. 5057 because macOS keeps 5000 for AirPlay Receiver.
      - "127.0.0.1:${REGISTRY_PORT:-5057}:5000"
    volumes:
      - registry-data:/var/lib/registry
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--spider", "http://127.0.0.1:5000/v2/"]
      interval: 3s
      timeout: 3s
      retries: 10
    restart: unless-stopped
    mem_limit: 256m
    cpus: 0.5
    pids_limit: 64
```

- The registry image itself is pinned by digest.
- `127.0.0.1:${REGISTRY_PORT:-5057}:5000` publishes the container's 5000 on the host's loopback only.
- `registry-data:/var/lib/registry` stores uploaded layers on a volume, so they survive `docker compose down`.
- The health check `wget --spider http://127.0.0.1:5000/v2/` asks the registry API root; a 200 answer means it is up.

```bash
#!/usr/bin/env bash
# Build the service (v3), push it to the local registry, deploy it from the registry by digest and call it.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "${ROOT}"

say "Build svc:v3 (multi-stage, distroless, non-root, bases pinned by digest) with the token as a build secret"
docker build --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v3 --build-arg "COMMIT=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" --tag "${REGISTRY}/svc:v3" .

say "Push it to the local registry"
digest="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
echo "pushed ${REGISTRY}/svc:v3 as ${digest}"

say "Deploy by digest: the name below cannot change meaning, even if the tag v3 is moved"
export SVC_IMAGE="${REGISTRY}/svc@${digest}"
docker compose --profile deploy up --detach --wait svc
port="${SVC_PORT:-8089}"
echo "GET /health  -> $(curl -fsS "http://127.0.0.1:${port}/health")"
echo "GET /version -> $(curl -fsS "http://127.0.0.1:${port}/version")"
echo "user         -> $(docker inspect --format '{{.Config.User}}' "$(docker compose --profile deploy ps -q svc)")"
echo "health       -> $(docker inspect --format '{{.State.Health.Status}}' "$(docker compose --profile deploy ps -q svc)")"
```

- `docker push ... | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1` reads the push output and extracts the digest from the line `v3: digest: sha256:... size: ...`.
- `export SVC_IMAGE="${REGISTRY}/svc@${digest}"` then `docker compose --profile deploy up --detach --wait svc` deploys by digest. The compose file's `image: ${SVC_IMAGE:-...}` default is a digest of all zeros, so forgetting the variable fails to pull instead of running a moving tag.

The digest test, abridged:

```bash
say "push v3, then move the tag v3 to a different image"
docker build --quiet --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v3 --tag "${REGISTRY}/svc:v3" . > /dev/null
first="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
docker build --quiet --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=other --tag "${REGISTRY}/svc:other" . > /dev/null
docker tag "${REGISTRY}/svc:other" "${REGISTRY}/svc:v3"
second="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
echo "v3 was ${first}; after the move it is ${second}"
check "the tag now points at a different digest" "$([ "${first}" != "${second}" ] && echo different || echo same)" different

say "run by the first digest and by the moved tag"
docker rmi -f "${REGISTRY}/svc:v3" "${REGISTRY}/svc:other" > /dev/null
by_digest="$(serve_and_get "${REGISTRY}/svc@${first}" 18083 /version)"
by_tag="$(serve_and_get "${REGISTRY}/svc:v3" 18084 /version)"
CLEANUP_IMAGES+=("${REGISTRY}/svc@${first}")
echo "by digest: ${by_digest}"
echo "by tag:    ${by_tag}"
check "the digest deploy still runs the first image" "$(echo "${by_digest}" | jq -r .version)" v3
check "the moved tag runs the other image" "$(echo "${by_tag}" | jq -r .version)" other
```

It pushes `v3`, builds a different image (`VERSION=other`), tags it `v3` and pushes it (the digest changes), removes the local images, then runs by the first digest and by the tag. `/version` shows `v3` for the digest and `other` for the moved tag.

## Try it yourself

1. Start it: `make up`. Expected: `Container shrink-and-harden-registry-1 Healthy`.
2. Ask it: `curl -s localhost:5057/v2/_catalog`. Expected: `{"repositories":[]}` at first, then `{"repositories":["svc"]}` after `make run`.
3. List tags: `curl -s localhost:5057/v2/svc/tags/list`. Expected: `{"name":"svc","tags":["v3", ...]}`.
4. Get a digest without pulling: `curl -sI -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' localhost:5057/v2/svc/manifests/v3 | grep -i docker-content-digest`. Expected: `Docker-Content-Digest: sha256:...`.

## Mistakes people make

- Deploying `latest` or any tag and assuming it stays the same.
- Publishing a registry on all network interfaces without authentication.
- Forgetting the registry volume: `down -v` deletes the stored images.
- Port clashes (5000 on a Mac).

## Check yourself

1. What is a digest? *A SHA-256 fingerprint of the image manifest; it names exact content.*
2. What happens to the old image when a tag is moved? *It stays stored and is still reachable by its digest.*
3. How does the deploy script learn the digest? *It parses the line printed by `docker push`.*
4. Why is the compose default a zero digest? *So a missing variable fails loudly.*
5. Why publish on `127.0.0.1`? *Only this machine can reach the unauthenticated registry.*

## Further reading

- Docker Registry (distribution): <https://distribution.github.io/distribution/>
- Image digests: <https://docs.docker.com/reference/cli/docker/image/pull/>
- OCI image spec (manifests): <https://github.com/opencontainers/image-spec/blob/main/manifest.md>
