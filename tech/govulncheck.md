# govulncheck

## What it is

govulncheck is Go's official tool for finding **known vulnerabilities** in the code you use. It looks at the packages and the standard library version your program depends on and compares them with the Go vulnerability database (`vuln.go.dev`). Unlike a plain dependency list, it checks whether your code actually **calls** the vulnerable function. This repository runs `govulncheck@v1.1.4`.


**Words used in this note**

- **package**: Code written by someone else, bundled so that you can install it and use it in your project.
- **database**: A program that stores data in an organized way and answers questions about it. PostgreSQL is one.
- **compiler**: A program that turns source code into machine code that the computer can run directly.
- **container**: A process (or a group of processes) run in isolation, with its own view of files, network and process list, but sharing the host's kernel.
- **exit code**: A number a program returns when it ends. 0 means success; any other number means failure. A shell keeps the last one in `$?`.
- **mount**: To make a folder or volume appear at a chosen path inside a container.
- **cache**: Saved results that are reused so slow work is not repeated.
- **image**: A read-only bundle of files and settings from which containers are started.

## Why this repository uses it

The template says dependencies are "checked by the CI's audit step". For a Go service with no third-party modules the dependencies are the compiler's own standard library. This tool earned its place: on Go 1.25.14 it reported ten standard-library vulnerabilities in code this service really uses (for example in `net/http` and `crypto/x509`), fixed only in the 1.26 line. The repository moved to Go 1.26 because of it.

## Where it appears

| Path | What it does |
| --- | --- |
| `Makefile` | `make audit` runs `go run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./...` in the pinned Go container. |
| `.github/workflows/ci.yml` | Runs `make audit`. |

## How it works underneath

govulncheck builds the call graph of your program: which functions can call which. For each vulnerability in the database it knows the vulnerable functions and the fixed version. It reports a vulnerability only if the call graph reaches a vulnerable function ("affected") and mentions others as informational. The exit code is non-zero when something affects you.

`go run package@version` downloads that exact version of a tool, builds it and runs it, without adding it to `go.mod`.

## Walkthrough of this repository's use

```makefile
audit: ## govulncheck: known vulnerabilities in the module and the standard library
```

(The next line of the Makefile is the recipe: `$(DOCKER_GO) $(GO_IMAGE) go run $(GOVULNCHECK) ./...`, where `GOVULNCHECK := golang.org/x/vuln/cmd/govulncheck@v1.1.4`.)

- `$(DOCKER_GO)` is the Docker run prefix that mounts the project and the Go caches; `$(GO_IMAGE)` is the pinned Go image.
- `./...` means every package below the current folder.

A failing run printed lines of this shape (abridged):

```text
Vulnerability #2: GO-2026-6617
    Found in: net/http@go1.25.14
    Fixed in: net/http@go1.26.9
Your code is affected by 10 vulnerabilities from the Go standard library.
```

After the move to the image `golang:1.26-bookworm` (Go 1.26.10) the run is clean.

## Try it yourself

1. Run it: `make audit`. Expected: `No vulnerabilities found.` (needs internet for the database).
2. See what it checks against: run with `-show verbose` (append to the `go run` line) to list modules and packages it scanned.
3. Try an old toolchain: replace the image tag in a copy of the Makefile with an older Go patch release and run `make audit`. Expected: findings that name the fixed version.
4. Read an advisory: open <https://pkg.go.dev/vuln/GO-2026-6617> (the id in the output).

## Mistakes people make

- Treating "no third-party dependencies" as "no vulnerabilities": the standard library has them too.
- Ignoring findings that say "affected" because "we only run it internally".
- Pinning the toolchain forever. Pins need updating when the database says so.

## Check yourself

1. What does govulncheck compare? *Your packages and Go version against the Go vulnerability database.*
2. How is it different from a plain version list? *It checks whether your code can call the vulnerable function.*
3. What fixed the ten findings here? *Moving from Go 1.25.14 to 1.26.*
4. What does `go run pkg@version` do? *Builds and runs that tool without changing `go.mod`.*
5. Why audit a project with no dependencies? *The standard library is also a dependency.*

## Further reading

- govulncheck: <https://go.dev/doc/security/vuln/>
- The vulnerability database: <https://pkg.go.dev/vuln/>
- Tutorial: <https://go.dev/doc/tutorial/govulncheck>
