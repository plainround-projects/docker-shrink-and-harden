# The `netrc` credentials file

## What it is

`.netrc` is an old Unix file that stores login names and passwords for network hosts, one machine per entry. Programs such as `curl`, `git` and the Go tool read it to log in to servers automatically. The format is lines of words: `machine HOST login NAME password SECRET`. It lives in the user's home folder, and programs refuse it if other users can read it.


**Words used in this note**

- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **image**: A read-only bundle of files and settings from which containers are started.
- **layer**: One step of an image build, stored as its own set of file changes. Unchanged layers are reused from the cache.
- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **mount**: To make a folder or volume appear at a chosen path inside a container.
- **cache**: Saved results that are reused so slow work is not repeated.

## Why this repository uses it

The lesson invents a **private package server**, `packages.internal.example`, that needs a token to download a Go module. The token is passed to `go mod download` through a `.netrc`. The point of the lesson is how to give the builder that file **without leaving it in the image**.

Nothing real is at risk: the token is the made-up `demo-token-123`, and nothing in the project contacts that host. The service has no private dependency, so the credentials are never actually presented anywhere.

## Where it appears

| Path | What it does |
| --- | --- |
| `netrc.example` | Committed. One line: the pretend host, the user `ci` and the demo token. |
| `netrc` | Not committed (ignored). `make up` copies it from the example. |
| `build/history/v0.Dockerfile` | Writes the token into `/root/.netrc` in a layer (the mistake). |
| `Dockerfile`, `v2.Dockerfile` | `--mount=type=secret,id=netrc,target=/root/.netrc`: the file is present only during `go mod download`. |
| `scripts/lib.sh`, `deploy.sh`, `sbom.sh` | Pass `--secret id=netrc,src=./netrc` to the build. |

## How it works underneath

For a normal `go mod download`, Go fetches modules from the public proxy. For a **private** module it contacts the module's host directly over HTTPS, and the HTTPS client looks for credentials in `~/.netrc` (that is, `$HOME/.netrc`, which for root is `/root/.netrc`). A **secret mount** makes BuildKit present a file from the build client at a chosen path for one `RUN` command only. It is a temporary mount, not part of the image layer, and it is never written to the build cache.

## Walkthrough of this repository's use

```text
machine packages.internal.example login ci password demo-token-123
```

- `machine packages.internal.example` names the server the credentials are for.
- `login ci` and `password demo-token-123` are the user name and token.

The two ways to deliver it, side by side:

```dockerfile
ARG PKG_TOKEN
WORKDIR /src
COPY . .
RUN echo "machine packages.internal.example login ci password ${PKG_TOKEN}" > /root/.netrc && go mod download && go build -o /app ./cmd/svc
```

The mistake: the token goes in through `ARG` and is written into a file by `RUN`; both the argument and the command text are saved in the image history.

```dockerfile
RUN --mount=type=secret,id=netrc,target=/root/.netrc,required=false \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
```

The fix: the build is started with `docker build --secret id=netrc,src=./netrc ...`. During that one `RUN` the file appears at `/root/.netrc`; afterwards it is gone. `required=false` lets a build without the secret succeed.

The test that proves the difference: `tests/e2e/01_token_leak_and_secret_mount.sh` greps `docker history --no-trunc` for `demo-token-123` (found in v0, count 2) and exports the v2 and v3 file systems to check that no `netrc` file exists in them.

## Try it yourself

1. See the file: `cat netrc.example`. Expected: the one line above.
2. Prove it is ignored: `git check-ignore -v netrc`. Expected: the `.gitignore` rule `/netrc`.
3. Show the leak: after `make measure`, `docker history --no-trunc svc:v0 | grep demo-token`. Expected: two lines.
4. Show its absence: `docker history --no-trunc svc:v3 | grep -ci demo-token`. Expected: `0`.

## Mistakes people make

- Passing tokens with `--build-arg` or `ENV`.
- Committing the real credentials file; commit only an example with fake values.
- Leaving permissive file modes on a real `.netrc`; many tools reject it.
- Assuming `rm` in a later layer deletes the secret from history.

## Check yourself

1. What does a netrc entry contain? *A machine name, a login and a password.*
2. Why is the token a leak in v0? *Build arguments and the `RUN` text are stored in the image history.*
3. What does a secret mount do? *Provides a file for one command only, never saved in a layer.*
4. Why `required=false`? *The same Dockerfile builds where there is no private server.*
5. Is the demo token real? *No. It is made up, and nothing contacts the host.*

## Further reading

- curl's `.netrc` description: <https://everything.curl.dev/usingcurl/netrc.html>
- Go private modules: <https://go.dev/ref/mod#private-modules>
- Build secrets: <https://docs.docker.com/build/building/secrets/>
