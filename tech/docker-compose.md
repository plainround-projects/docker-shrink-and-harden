# Docker Compose

## What it is

Docker Compose starts several containers together from one YAML file that lists **services**, **volumes** and **networks**. `docker compose up` creates what is missing and starts it. This repository uses Compose v2 (the `docker compose` command, 2.23).


**Words used in this note**

- **hash**: A short fingerprint computed from the bytes of a file. Change one byte and the fingerprint changes. SHA-256 is a common method; its result is called a digest.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **shell**: A program that reads the commands you type (or a script's lines) and starts other programs for you. Bash is a shell.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **binary**: A file of machine code that the computer runs directly, as opposed to text that another program must read.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.

## Why this repository uses it

The lesson needs a local registry to push to, and then a place to deploy the finished image by digest. One compose file holds both, and uses a **profile** so the deployed service only starts when asked.

## Where it appears

| Path | What it does |
| --- | --- |
| `docker-compose.yml` | Defines `registry` (always) and `svc` (profile `deploy`). |
| `Makefile` | `make up` starts only the registry; `make down` stops both. |
| `scripts/deploy.sh` | Sets `SVC_IMAGE` to a digest and starts `svc`. |

## How it works underneath

Compose reads the file and the `.env` next to it, replaces `${NAME}` and `${NAME:-default}` with values, and calls the Docker engine to create containers. A service with `profiles: [deploy]` is ignored unless you pass `--profile deploy`. `--wait` makes `up` wait until each service with a health check is healthy.

## Walkthrough of this repository's use

```yaml
# A local registry, so pushes, digests and pulls can be tried without an account anywhere, and the service
# deployed from it by digest. `make up` starts only the registry; `make run` deploys the service.
name: shrink-and-harden

services:
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

  # The service as deployed: from the registry, by digest, read-only, no capabilities.
  # SVC_IMAGE must be a digest reference; scripts/deploy.sh sets it. The default is a digest that matches nothing, so a
  # deploy without it fails to pull instead of running whatever a tag points to today.
  svc:
    image: ${SVC_IMAGE:-localhost:5057/svc@sha256:0000000000000000000000000000000000000000000000000000000000000000}
    profiles: [deploy]
    ports:
      - "127.0.0.1:${SVC_PORT:-8089}:8080"
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    mem_limit: 64m
    cpus: 0.5
    pids_limit: 64
    stop_grace_period: 10s
    restart: unless-stopped

volumes:
  registry-data:
```

### `registry`

See `docker-registry.md`. In Compose terms: `ports` publishes with a loopback address and a defaulted variable; `volumes` names `registry-data` (declared at the bottom); `healthcheck.test: ["CMD", "wget", ...]` runs a program in the container without a shell; `mem_limit`, `cpus`, `pids_limit` cap memory, processors and the number of processes; `restart: unless-stopped` restarts it after a crash or a Docker restart unless you stopped it.

### `svc` (the deployed service)

- `image: ${SVC_IMAGE:-localhost:5057/svc@sha256:000...}`: the deploy script sets the variable to the pushed digest. The default is a digest that matches nothing, so a deploy without it fails to pull.
- `profiles: [deploy]` keeps it out of `make up`.
- `read_only: true` makes the root file system read-only. The program writes no files, so it needs nothing writable.
- `cap_drop: [ALL]` removes all Linux capabilities (slices of root's powers). `security_opt: no-new-privileges:true` stops a process gaining rights through setuid programs.
- `mem_limit: 64m`, `cpus: 0.5`, `pids_limit: 64`: small limits suit an 8 MB program.
- `stop_grace_period: 10s`: how long Docker waits after `SIGTERM` before `SIGKILL`. The service's own shutdown timeout is 8 seconds, inside that.
- `ports: "127.0.0.1:${SVC_PORT:-8089}:8080"` publishes the container's 8080 on the host's 8089.
- The image's own `HEALTHCHECK` (the binary's `healthcheck` subcommand) is what `--wait` waits for.

## Try it yourself

1. Check the file: `docker compose config --quiet`. Expected: no output, exit 0 (the default digest makes `SVC_IMAGE` optional).
2. Start the registry only: `make up`. Expected: `Container shrink-and-harden-registry-1 Healthy`.
3. Deploy: `make run`. Expected: `GET /health -> ok`, `user -> nonroot:nonroot`, `health -> healthy`.
4. See that `svc` needs the profile: `docker compose ps` before `make run` lists only the registry.
5. Stop everything: `make down`. Expected: both containers removed; the `registry-data` volume stays.

## Mistakes people make

- Expecting `docker compose up` to start services in a profile.
- Forgetting that `down -v` removes the registry's stored images.
- Using a moving tag in `SVC_IMAGE`.

## Check yourself

1. What does `profiles` do? *Keeps a service from starting unless its profile is requested.*
2. Why is the default image reference all zeros? *A deploy without `SVC_IMAGE` fails instead of running something unintended.*
3. What does `read_only: true` forbid? *Writing to the container's root file system.*
4. What does `cap_drop: [ALL]` remove? *Every Linux capability.*
5. What does `--wait` wait for? *Services with health checks to become healthy.*

## Further reading

- Compose file reference: <https://docs.docker.com/reference/compose-file/>
- Profiles: <https://docs.docker.com/compose/how-tos/profiles/>
- `docker compose up`: <https://docs.docker.com/reference/cli/docker/compose/up/>
