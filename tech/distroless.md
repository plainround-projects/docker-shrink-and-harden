# Distroless images (`gcr.io/distroless/static-debian12:nonroot`)

## What it is

A **distroless** image contains your program and only what it needs to run: certificate authorities, time-zone data, the `/etc/passwd` entries for a few users and little else. It has **no shell, no package manager and no `ls`**. "Distroless" means it carries no Linux distribution's tools. This repository uses `static-debian12:nonroot`: the "static" variant is meant for programs with no C library dependency, "debian12" names its Debian base release, and "nonroot" selects the default user `nonroot` (user id 65532).

## Why this repository uses it

Step 4 of the lesson asks for a smaller, safer runtime base. Fewer files means fewer packages for a scanner to report (Trivy finds 0 critical and 0 high), and an attacker who breaks into the program has no shell to use. The image is 8 MB.

## Where it appears

| Path | What it does |
| --- | --- |
| `Dockerfile` | The runtime stage: `FROM gcr.io/distroless/static-debian12:nonroot@sha256:...`. |
| `tests/e2e/04_distroless_nonroot_fewer_findings.sh` | Checks the user, the missing shell and the scanner counts. |
| `README.md` | "Debugging without a shell": what to do instead of `docker exec sh`. |

## How it works underneath

An image is a stack of layers; a distroless one has very few files, so the layer is tiny. The program must be **fully static**: if it needed a shared library (for example the C library `libc`), the loader would not find it and the container would fail at start with a confusing "no such file or directory" for the program itself. That is why the build stage uses `CGO_ENABLED=0`.

Without a shell, `docker exec -it svc sh` fails. Debugging uses other means: logs, `docker inspect`, `docker debug` (where available), or a second container that shares the first one's process and network namespaces. The health check cannot call `curl`, so the service binary has a `healthcheck` subcommand.

## Walkthrough of this repository's use

```dockerfile
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
# A distroless image has no shell or curl, so the binary checks itself.
HEALTHCHECK --interval=15s --timeout=3s --start-period=3s --retries=3 CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
```

- `USER nonroot:nonroot` repeats the base's default explicitly, so the Dockerfile does not rely on the tag name alone.
- `HEALTHCHECK ... CMD ["/app", "healthcheck"]` runs `/app` with the `healthcheck` argument; Go code in `cmd/svc/main.go` sends `GET /health` to `127.0.0.1` and exits 0 or 1.

The test:

```bash
check "the image declares a non-root user" "$(docker inspect --format '{{.Config.User}}' svc:v3)" "nonroot:nonroot"
check "the smoke test still passes: GET /health" "$(serve_and_get svc:v3 18082 /health)" "ok"
check "there is no shell to exec into" "$(docker run --rm --entrypoint sh svc:v3 -c true > /dev/null 2>&1 && echo shell || echo none)" none
count_v1="$(high_critical svc:v1)"
count_v3="$(high_critical svc:v3)"
```

- `docker inspect --format '{{.Config.User}}'` must print `nonroot:nonroot`.
- `docker run --rm --entrypoint sh svc:v3 -c true` must **fail**: the check prints `none` when no shell exists.
- The scanner counts for v1 and v3 are compared; v3 must not be higher.

## Try it yourself

1. Look for a shell: `docker run --rm --entrypoint sh svc:v3 -c true; echo $?`. Expected: an error that `sh` is not found and a non-zero exit.
2. Check the user: `docker inspect svc:v3 --format '{{.Config.User}}'`. Expected: `nonroot:nonroot`.
3. Debug without a shell: with the service running as `svc`, `docker run --rm -it --pid=container:svc --network=container:svc alpine sh`, then `wget -qO- localhost:8080/health`. Expected: `ok`.
4. Size: `docker image ls svc`. Expected: about 8 MB for v3.

## Mistakes people make

- Putting a dynamic binary on a static image.
- Needing a shell during an incident and having no plan. The README lists one.
- Using the `:debug` tag (it adds BusyBox) in production.
- Assuming "no shell" means "secure". It reduces what an attacker can do; it does not replace updates.

## Check yourself

1. What is missing from a distroless image? *A shell, a package manager and most system tools.*
2. Why `CGO_ENABLED=0`? *The static image has no C library for a dynamic binary.*
3. Why does the binary have a `healthcheck` command? *No `curl` or shell exists to run a check.*
4. What is the default user of the `nonroot` tag? *`nonroot`, user id 65532.*
5. How do you debug a distroless container? *Logs, inspect, or a second container sharing its namespaces.*

## Further reading

- Distroless: <https://github.com/GoogleContainerTools/distroless>
- Docker debug: <https://docs.docker.com/reference/cli/docker/debug/>
- Sharing namespaces (`--pid`, `--network`): <https://docs.docker.com/reference/cli/docker/container/run/>
