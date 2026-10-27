# BuildKit and `docker buildx`

## What it is

**BuildKit** is Docker's modern image builder. It builds independent steps in parallel, supports secret and cache mounts, and can attach extra documents (an SBOM and provenance) to an image. **buildx** is the `docker` command's front end to BuildKit: `docker buildx build`, `docker buildx create`, `docker buildx imagetools inspect`. A **builder** is a BuildKit instance. This repository uses buildx 0.11 on Docker Desktop and BuildKit 0.33 inside the builder container.

## Why this repository uses it

Three lesson steps need BuildKit features: the secret mount (step 3), cache mounts (step 3), and the SBOM and provenance (step 6). The SBOM needs a builder of the `docker-container` kind, which this repository creates for itself. A private builder also has its own cache, so a cold build here is really cold and does not depend on other work on the machine.

## Where it appears

| Path | What it does |
| --- | --- |
| `Makefile` (`builder` target) | Creates the builder `shrink-and-harden`. |
| `scripts/lib.sh` (`build`, `build_version`) | Runs `docker buildx build --builder ... --load`. |
| `scripts/sbom.sh` | Builds v4 with `--sbom=true --provenance=mode=max --push`. |
| `scripts/measure.sh` | Empties the builder's cache mounts before each cold build. |
| `tests/e2e/06_sbom_and_provenance.sh` | Reads the attestations with `docker buildx imagetools inspect`. |

## How it works underneath

The default builder runs inside the Docker engine and shares its image store. A **`docker-container` builder** runs BuildKit in its own container with its own cache, which gives access to more features. Its results do not appear in `docker images` unless you ask: `--load` copies the result into the local engine, `--push` sends it to a registry.

`--driver-opt network=host` makes the builder container share the host network namespace (inside Docker's VM), so a registry published on `localhost:5057` is reachable for `--push`.

**Attestations** are small signed-like documents stored beside the image in the registry as extra manifests: an **SBOM** (what packages are inside) and **provenance** (how and where it was built). They are not layers; the image itself is unchanged.

## Walkthrough of this repository's use

```makefile
builder: ## create the BuildKit builder used for cache measurements, SBOM and provenance (docker-container driver)
	@docker buildx inspect $(BUILDER) > /dev/null 2>&1 || \
	  docker buildx create --name $(BUILDER) --driver docker-container --driver-opt network=host > /dev/null
	@docker buildx inspect $(BUILDER) --bootstrap > /dev/null
```

- `docker buildx inspect NAME` succeeds if the builder exists; `||` runs the create command otherwise.
- `docker buildx create --name shrink-and-harden --driver docker-container --driver-opt network=host` makes it.
- `docker buildx inspect --bootstrap` starts it so the first build is not slowed by startup.

```bash
build() {
  local version="$1" dockerfile="$2" context="$3"
  shift 3
  docker buildx build --builder "${BUILDER}" --load --file "${dockerfile}" --tag "svc:${version}" "$@" "${context}"
}
# Arguments by version: v0 takes the token as a build argument (the mistake), v1 does not use it, v2 and later take it
# as a secret.
args_for() {
  case "$1" in
    v0) printf '%s\n' --build-arg "PKG_TOKEN=${PKG_TOKEN:-demo-token-123}" ;;
    v1) ;;
    *) printf '%s\n' --secret "id=netrc,src=${ROOT}/netrc" ;;
  esac
}
dockerfile_for() {
  case "$1" in
    v0 | v1 | v2) echo "${ROOT}/build/history/$1.Dockerfile" ;;
    *) echo "${ROOT}/Dockerfile" ;;
  esac
}
build_version() { # build_version <version> <context> [extra args]: the right Dockerfile and secret arguments for a version
```

- `docker buildx build --builder B --load --file F --tag svc:vN "$@" CONTEXT` builds with that builder and loads the result into the local engine.
- `args_for` chooses the right flags per version: v0 gets `--build-arg PKG_TOKEN=...` (the mistake), v1 none, v2 and later `--secret id=netrc,src=./netrc` (the secret mount).

```bash
#!/usr/bin/env bash
# Build v4: the same Dockerfile as v3, built with an SBOM and provenance attestation and pushed to the local registry.
# Then answer "which packages are inside, and was it built from this commit?" from the registry alone.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "${ROOT}"

say "Build and push svc:v4 with --sbom=true --provenance=mode=max (needs the docker-container builder)"
docker buildx build --builder "${BUILDER}" --sbom=true --provenance=mode=max --push \
  --secret "id=netrc,src=${ROOT}/netrc" --build-arg VERSION=v4 --build-arg "COMMIT=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" --tag "${REGISTRY}/svc:v4" .

say "Packages in the SBOM"
docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .SBOM }}' | jq -r '.SPDX.packages[] | select(.versionInfo != null) | "\(.name) \(.versionInfo)"' | sort

say "Does the image contain the Go standard library, and which version?"
docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .SBOM }}' | jq -r '.SPDX.packages[] | select(.name == "stdlib") | "\(.name) \(.versionInfo)"'

say "Provenance: what built this image, and from which pinned inputs"
provenance="$(docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .Provenance }}')"
echo "${provenance}" | jq -r '"build type: \(.SLSA.buildDefinition.buildType)"'
echo "${provenance}" | jq -r '.SLSA.buildDefinition.resolvedDependencies[]? | "input: \(.uri) \(.digest | to_entries[0] | "\(.key):\(.value[0:19])...")"'
```

- `--sbom=true` asks BuildKit's scanner to list the packages; `--provenance=mode=max` records the most detail (build inputs, base images by digest, arguments). `--push` is required because attestations live in the registry.
- `docker buildx imagetools inspect REF --format '{{ json .SBOM }}'` prints the SBOM as JSON; `jq` filters it (see `jq.md`). `.Provenance` prints the provenance.

```bash
forget_cache_mounts() {
  docker buildx prune --builder "${BUILDER}" --force --filter type=exec.cachemount > /dev/null 2>&1 \
    || docker buildx prune --builder "${BUILDER}" --force > /dev/null
}
touch_source() { printf '\n// one-line change for the warm build: %s at %s\n' "$1" "$(date +%s)" >> "${WORK}/cmd/svc/main.go"; }
```

`docker buildx prune --builder B --force --filter type=exec.cachemount` removes only the cache-mount data on the project's own builder (not layers, not other builders), so the next build must download modules and recompile the standard library.

## Try it yourself

1. Create it: `make builder`. Expected: no output; then `docker buildx ls` lists `shrink-and-harden` with driver `docker-container`.
2. Build one version: `make sbom`. Expected: lines `Packages in the SBOM`, then `stdlib go1.26.10`.
3. Read the attestations: `docker buildx imagetools inspect localhost:5057/svc:v4`. Expected: a manifest list with the image and two `unknown/unknown` attestation entries.
4. Count compiled packages cold and warm: `tests/e2e/03_warm_build_uses_the_cache.sh`. Expected: `cold 196, warm 1`.

## Mistakes people make

- Expecting `--load` to work together with attestations on a plain engine; use `--push` to a registry.
- Forgetting that the builder keeps its own cache: `docker system prune` does not clear it. `make clean` removes the builder.
- Using `--no-cache` and expecting cache mounts to be emptied. They are separate; the measure script prunes them explicitly.

## Check yourself

1. What is a builder? *A BuildKit instance that runs builds.*
2. Why `--driver docker-container`? *The default engine builder cannot attach SBOM and provenance.*
3. What does `--load` do? *Copies the built image into the local Docker engine.*
4. Where do attestations live? *In the registry, as extra manifests beside the image.*
5. What does `network=host` change? *The builder can reach `localhost:5057` where the registry listens.*

## Further reading

- BuildKit: <https://docs.docker.com/build/buildkit/>
- `docker buildx` reference: <https://docs.docker.com/reference/cli/docker/buildx/>
- Build drivers: <https://docs.docker.com/build/builders/drivers/>
- Attestations: <https://docs.docker.com/build/metadata/attestations/>
