# Docker (the engine and the command line)

## What it is

Docker runs programs in isolated boxes called **containers**. A container looks like a small computer with its own files, process list and network, but it is an ordinary process on the host, fenced in by Linux kernel features. The `docker` command talks to a background service, the **Docker engine**, which builds **images**, starts containers and manages **networks** and **volumes**. On a Mac, a small hidden Linux virtual machine (started by Docker Desktop) provides the Linux kernel. This repository was built with engine 24.0.6.

## Why this repository uses it

Everything the lesson measures is about images and containers: how big they are, how long they take to build, what is inside them, what user they run as, and how they stop.

## Where it appears

| Path | What it does with Docker |
| --- | --- |
| `Dockerfile`, `build/history/*.Dockerfile` | Image recipes (see `dockerfile.md`). |
| `docker-compose.yml` | The registry and the deployed service (see `docker-compose.md`). |
| `Makefile` | Runs every tool (Go, linters) in a pinned container, so the host needs only Docker. |
| `scripts/`, `tests/e2e/` | Build, run, inspect and remove images and containers. |

## How it works underneath

- **Namespaces** give a process its own view of the system: its own process list (so the container's first process is PID 1), network, mounts and host name.
- **cgroups** limit what the process may use: memory, processor time, the number of processes. A container that exceeds its memory limit is killed by the kernel (exit code 137).
- **Layers**: an image is a stack of read-only layers; a container adds a thin writable layer. Files written there vanish with the container unless they are on a **volume** or **bind mount**.
- `docker stop` sends `SIGTERM` to PID 1, waits (ten seconds by default), then sends `SIGKILL`. A program that handles `SIGTERM` exits with code 0; one that does not shows exit code 137.
- The **Docker socket** (`/var/run/docker.sock`) is how the `docker` command reaches the engine. A container that is given the socket (as Trivy is here) can control the engine, so it is only done for trusted tools.

## Walkthrough of this repository's use

Commands used in this repository, and their flags:

- `docker build --secret id=netrc,src=./netrc --build-arg VERSION=v3 --tag localhost:5057/svc:v3 .` builds an image, passes a build secret and a build argument, and names it.
- `docker push REF` uploads it to the registry and prints the digest.
- `docker run -d --name N -p 127.0.0.1:18081:8080 IMAGE` starts a container in the background, names it, and publishes its port 8080 on the host's loopback port 18081.
- `docker run --rm --entrypoint sh IMAGE -c true` replaces the image's entrypoint with `sh`; it fails on distroless, proving there is no shell.
- `docker inspect --format '{{.Config.User}}' IMAGE` prints one field of the JSON description using Go template syntax.
- `docker history --no-trunc IMAGE` lists the layers with their full instructions (this is where a leaked build argument shows).
- `docker image inspect --format '{{.Size}}' IMAGE` prints the size in bytes.
- `docker create` + `docker export CONTAINER | tar -t` lists the files in an image's file system without running it (used to prove no `netrc` file exists).
- `docker rm -f`, `docker rmi -f` remove containers and images.
- `docker compose ...`, `docker buildx ...` are plugins (see their notes).

The tool containers in the Makefile:

```makefile
DOCKER_GO := docker run --rm -v "$(CURDIR)":/src -v shrink-gomod:/go/pkg/mod -v shrink-gobuild:/root/.cache/go-build -w /src
```

- `-v "$(CURDIR)":/src` mounts the project at `/src`; `-w /src` makes it the working folder.
- `-v shrink-gomod:/go/pkg/mod -v shrink-gobuild:/root/.cache/go-build` are **named volumes** holding Go's module and build caches, so repeated test runs are fast.
- `--rm` deletes the container after the command. No Go is installed on the Mac: the pinned image `golang:1.26-bookworm@sha256:...` is the toolchain.

## Try it yourself

1. Engine version: `docker version --format '{{.Server.Version}}'`. Expected: `24.0.6`.
2. Run a throw-away container: `docker run --rm alpine:3.24.3 echo hello`. Expected: `hello`.
3. See the user of the final image: `docker inspect svc:v3 --format '{{.Config.User}}'`. Expected: `nonroot:nonroot`.
4. List layers: `docker history svc:v3`. Expected: a few lines, the largest only a few megabytes.
5. See the signal rule: `docker run -d --name t alpine:3.24.3 sleep 1000; time docker stop t; docker inspect t --format '{{.State.ExitCode}}'; docker rm t`. Expected: about ten seconds, then `137`.

## Mistakes people make

- Storing data inside a container instead of on a volume.
- Treating a tag as fixed.
- Handing the Docker socket to untrusted containers.
- Leaving containers and images around: they use memory, ports and disk.

## Check yourself

1. How is a container different from a virtual machine? *A normal process fenced by namespaces and cgroups; it shares the host kernel.*
2. What does exit code 137 mean? *128 + 9: killed by `SIGKILL`, by the stop timeout or the kernel's memory limit.*
3. What does `docker history --no-trunc` reveal? *Every layer's full instruction, including build arguments.*
4. Why run Go tools in containers here? *The host needs only Docker, and the toolchain version is pinned.*
5. What does `-p 127.0.0.1:18081:8080` mean? *Host loopback port 18081 forwards to container port 8080.*

## Further reading

- Docker overview: <https://docs.docker.com/get-started/docker-overview/>
- `docker` CLI reference: <https://docs.docker.com/reference/cli/docker/>
- Resource constraints: <https://docs.docker.com/engine/containers/resource_constraints/>
- Formatting output: <https://docs.docker.com/engine/cli/formatting/>
