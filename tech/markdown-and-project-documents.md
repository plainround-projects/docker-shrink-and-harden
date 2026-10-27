# Markdown and the project documents

## What it is

Markdown is a way of writing formatted text in a plain text file. You add a few marks, and tools that understand Markdown (GitHub, editors, the Claude desktop app) show headings, lists, tables and code boxes. Every document in this repository is a `.md` file: `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, the decision records under `docs/adr/`, and the other files under `docs/`. `LICENSE` is plain text. This note teaches the marks and then explains what each document is for.


**Words used in this note**

- **image**: A read-only bundle of files and settings from which containers are started.
- **pipe**: The `|` symbol. It connects the output of the command on its left to the input of the command on its right.
- **terminal**: A window where you type commands as text and read the answers. The program inside it that reads your commands is the shell.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **layer**: One step of an image build, stored as its own set of file changes. Unchanged layers are reused from the cache.
- **binary**: A file of machine code that the computer runs directly, as opposed to text that another program must read.
- **mount**: To make a folder or volume appear at a chosen path inside a container.
- **cache**: Saved results that are reused so slow work is not repeated.
- **hash**: A short fingerprint computed from the bytes of a file. Change one byte and the fingerprint changes. SHA-256 is a common method; its result is called a digest.

## Why this repository uses it

The template says a repository must explain itself: how to run it, how it is built, what changed, why each big choice was made. Plain text in Markdown keeps those answers next to the code, under version control, and readable in any editor.

## Where it appears

| Path | What it does |
| --- | --- |
| `README.md` | The front page: what the project is, how to run, test and stop it, how each "Done when" line is proved. |
| `ARCHITECTURE.md` | The parts of the image pipeline, how they depend on each other, one request or run step by step, and the limits of the teaching build. |
| `CHANGELOG.md` | What changed in each version. |
| `docs/adr/*.md` | Architecture decision records: 4 short files, one per big choice. |
| `docs/measurements.md` | The measured size, vulnerability counts and build times of the five image versions, as a table. |
| `LICENSE` | The MIT license text. |
| `tech/*.md` | These notes. |

## How it works underneath

A Markdown file is just text. A program reads it line by line and applies a few rules.

- A line that starts with `#` is a heading. One `#` is the title, `##` a section, `###` a subsection.
- `- item` starts a bullet list; `1. item` starts a numbered list.
- `**word**` is bold; `*word*` is italic; a word between single backticks (`` `word` ``) is shown as code.
- Three backticks on a line of their own open and close a **fenced code block**. The word after the opening backticks (`bash`, `python`, `text`) names the language so the viewer can color it.
- `[text](address)` is a link. A link to a file in the same repository is a relative path, such as `[ARCHITECTURE.md](ARCHITECTURE.md)`; a link to a heading in the same file is `#heading-in-lower-case-with-hyphens`.
- A table has a header row, a separator row of dashes, and rows; cells are separated by `|`. A literal `|` inside a cell is written `\|`.
- A blank line separates paragraphs.

Markdown does not run anything. It is not code, but it is checked in the same way: it lives in Git, and a wrong command in a README is a bug like any other.

## Walkthrough of this repository's use

### README.md

The README starts with a table (lesson, planned hours, level, links), then the sections the template requires: Prerequisites, Setup, run, test, stop, "Done when" (a table where each line of the lesson's checklist has the command that proves it), Stretch goals, What is simplified for teaching, Project structure (a fenced block that draws the folder tree), Troubleshooting, and Author and license. Every command in it is meant to be copied into a terminal.

### ARCHITECTURE.md

Its first lines show its shape; the rest follows the same sections:

```markdown
# Architecture: the image pipeline

This document describes what the code, Dockerfiles and scripts in this repository do and why they are shaped this way. Component names match the lesson ("a compiled service, a local registry, five image versions"): the **service**, the **one-stage image v0**, the **multi-stage image v1**, **v2** with mounts, **v3** distroless and non-root, **v4** with an SBOM and provenance, and the **local registry**.

## Components and what each owns

| Component | Where it lives | What it owns |
| --- | --- | --- |
| **Service** | [`cmd/svc`](cmd/svc), [`internal`](internal) | A small Go HTTP service: `GET /health` answers `ok`, `GET /version` answers the build's version, commit and Go version as JSON, and `svc healthcheck` checks a running instance (the container's health command). Graceful shutdown on SIGTERM and SIGINT. |
| **v0: one stage** | [`build/history/v0.Dockerfile`](build/history/v0.Dockerfile) | The starting point: the full SDK image, the token as a build argument, the source and the compiler all in the shipped image. |
| **v1: multi-stage** | [`build/history/v1.Dockerfile`](build/history/v1.Dockerfile) | Compile in a build stage, ship a static binary on a slim Debian. |
| **v2: secret and cache mounts** | [`build/history/v2.Dockerfile`](build/history/v2.Dockerfile) | The token as a BuildKit secret mount, module and compiler caches as cache mounts. |
| **v3: distroless, non-root, pinned** | [`Dockerfile`](Dockerfile) | The shipped image: static binary on `distroless/static-debian12:nonroot`, both bases pinned by digest, `USER nonroot:nonroot`, a self-checking `HEALTHCHECK`. |
| **v4: SBOM and provenance** | `make sbom` ([`scripts/sbom.sh`](scripts/sbom.sh)) | The v3 Dockerfile built with `--sbom=true --provenance=mode=max` and pushed to the registry; the attestations are stored beside the image. |
| **Local registry** | service `registry` in [`docker-compose.yml`](docker-compose.yml), `registry:2` pinned by digest | Pushes, pulls and digests without an account anywhere. Listens on `127.0.0.1:5057`. |
| **Builder** | `shrink-and-harden`, a `docker-container` BuildKit builder with host networking ([`Makefile`](Makefile) target `builder`) | An isolated build cache, so a cold build is really cold and the measurements do not depend on what else is on the machine; the only driver that can attach an SBOM and provenance and push to a `localhost` registry. |
| **Measurements** | [`scripts/measure.sh`](scripts/measure.sh), [`docs/measurements.md`](docs/measurements.md) | Size, cold build, warm build, scanner counts and token lines in the history for every version. |
| **Done-when checks** | [`tests/e2e`](tests/e2e) | One script per Done-when line, run against real images. |

## Pattern: layers inside a small service, and a history of Dockerfiles
```

The sections are: Components and what each owns; the Pattern used (ports and adapters or layers, explained); Data flow (one request or run, step by step); Decisions and trade-offs; Failure modes the lesson teaches and how the code shows them; Limits of the teaching build against a production one; How to extend it. Its component names match the lesson's diagram, as the template requires.

### CHANGELOG.md

```markdown
# Changelog

All notable changes to this project are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-27

### Added

- `tech/`: 26 beginner-level notes, one per technology the repository uses (Go, Docker, BuildKit, distroless, the registry, Trivy, SBOM and provenance, Bash, Make, jq and the rest), each walking through this repository's own files, with an index.
- A small Go service (`GET /health`, `GET /version`, `svc healthcheck`) in layers: `domain`, `application`, `infrastructure` (configuration, build information, logging), `interfaces` (HTTP with graceful shutdown, the health command); the dependency rule is enforced by a test.
- Five versions of its image, each measured: v0 one stage on the full SDK image with the token as a build argument, v1 multi-stage, v2 secret and cache mounts, v3 distroless static and non-root with bases pinned by digest, v4 the same with an SBOM and provenance.
- A local registry in Compose, a deploy by digest, `make measure`, `make sbom`, and one end-to-end script per Done-when line.
- gofmt, go vet, golangci-lint, hadolint, shellcheck, govulncheck, and a CI workflow.
```

The format is "Keep a Changelog": a heading per version with the date (`## [0.1.0] - 2026-10-27`) and under it `### Added`, `### Changed`, `### Fixed`. The version numbers follow Semantic Versioning (MAJOR.MINOR.PATCH): 0.1.0 is the first version, and a number below 1.0.0 means the interface may still change.

### Architecture decision records

An **ADR** records one decision: why it was made, what else was possible, and what it costs. Every file has the same four headings: Context (the situation), Decision (what was chosen), Alternatives considered, Consequences (good and bad). Here is the first in full:

```markdown
# 1. Keep v0 to v2 as Dockerfiles in the tree; the root Dockerfile is v3

Status: accepted, 2026-10-27

## Context

The lesson is a story in numbers: five versions of one image, each measured. A reader needs to rebuild any version and see its numbers, and the repository should still ship one good `Dockerfile` that is not a museum.

## Decision

`build/history/v0.Dockerfile` to `v2.Dockerfile` are the first three versions, kept as they were at each step. The root `Dockerfile` is v3 and, built with `docker buildx build --sbom=true --provenance=mode=max`, v4: the lesson's table has the same Dockerfile for v3 and v4. `scripts/measure.sh` builds all five from one clean copy of the tree and writes `docs/measurements.md`. The git history has one commit per version, each with its measured row in the message.

## Alternatives considered

- **One Dockerfile with build arguments that switch each improvement on:** the story disappears and the flawed lines would sit inside conditionals.
- **Only the final Dockerfile, with the story in the README:** the README's numbers could not be reproduced.

## Consequences

- The history Dockerfiles are not linted and not used for anything but measurement and the history check. `.hadolint.yaml` and CI lint the root `Dockerfile` only.
- A change to the application source applies to every version, since all of them build the same tree. The base-image digests are repeated in each file; a bot that updates pinned digests has four places to touch.
```

The records in this repository, by title:

- `docs/adr/0001-pipeline-stages-as-separate-dockerfiles.md`: "1. Keep v0 to v2 as Dockerfiles in the tree; the root Dockerfile is v3".
- `docs/adr/0002-distroless-static-and-a-self-checking-binary.md`: "2. Distroless static as the runtime, and the binary checks itself".
- `docs/adr/0003-build-secrets-and-cache-mounts.md`: "3. A secret mount for the token, and cache mounts for speed".
- `docs/adr/0004-pin-by-digest-and-deploy-by-digest.md`: "4. Pin base images by digest; deploy the service by digest".

### Other documents under docs/

`docs/measurements.md` holds the measured size, vulnerability counts and build times for the five image versions, as a table. `make measure` produces the numbers; the file records them.

### LICENSE

```text
MIT License

Copyright (c) 2026 Sumit Srivastava
```

The MIT license lets anyone use, copy, modify and distribute the code, including commercially, as long as the copyright notice and the license text stay with it, and it comes with no warranty.

## Try it yourself

1. List every document: `git ls-files '*.md' LICENSE`. Expected: the files named in the table above.
2. See the headings of one document as an outline: `grep -n '^#' ARCHITECTURE.md`. Expected: the sections listed above, with line numbers.
3. Check a link target exists: `ls docs/adr`. Expected: `0001-pipeline-stages-as-separate-dockerfiles.md`, `0002-distroless-static-and-a-self-checking-binary.md`, `0003-build-secrets-and-cache-mounts.md`, `0004-pin-by-digest-and-deploy-by-digest.md`.
4. Read the changelog's newest entry: `sed -n 1,10p CHANGELOG.md`. Expected: the title, the format sentence and the `0.1.0` heading.

## Mistakes people make

- Documentation that drifts from the code. Here each README command was run, and the notes quote real lines from the files.
- Long lines of prose with no structure. Headings, short paragraphs and tables make a document searchable.
- A fenced code block with no language word, so nothing is highlighted.
- Absolute paths in links; they break when the repository is cloned elsewhere.

## Check yourself

1. What does a line starting with `##` mean? *A section heading, one level below the title.*
2. How do you show a command so that it can be copied? *In a fenced code block, with the language word `bash`.*
3. What are the four headings of an ADR? *Context, Decision, Alternatives considered, Consequences.*
4. What does `0.1.0` mean in a changelog? *Version 0, minor 1, patch 0: the first release, interface not yet frozen.*
5. What does the MIT license allow? *Use, copy, modify and distribute, with the notice kept and no warranty.*

## Further reading

- CommonMark specification (the core of Markdown), version 0.31.2: <https://spec.commonmark.org/0.31.2/>
- GitHub Flavored Markdown (tables, fenced code): <https://github.github.com/gfm/>
- Keep a Changelog 1.1.0: <https://keepachangelog.com/en/1.1.0/>
- Semantic Versioning 2.0.0: <https://semver.org/spec/v2.0.0.html>
- Architecture decision records: <https://adr.github.io/>
- The MIT license: <https://opensource.org/license/mit>
