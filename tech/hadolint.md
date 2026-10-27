# hadolint 2.12

## What it is

hadolint is a **linter for Dockerfiles**. It reads a Dockerfile and reports instructions that break good practice, with rule codes such as `DL3008` (Dockerfile rules) and, through the ShellCheck program built into it, `SC2086` (problems in the shell commands inside `RUN` lines). This repository runs `hadolint/hadolint:v2.12.0` as a container.

## Why this repository uses it

The template asks for `hadolint` in CI. The lesson's whole subject is a good, small, safe Dockerfile, so a tool that catches the classic mistakes (unpinned base, missing `USER`, shell-form commands) keeps it that way.

## Where it appears

| Path | What it does |
| --- | --- |
| `.hadolint.yaml` | Its settings. |
| `Makefile` | `lint` runs `docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" $(HADOLINT_IMAGE) hadolint - < Dockerfile`. |

## How it works underneath

hadolint parses the Dockerfile into instructions. Each rule looks at instructions, or at the shell text of `RUN`, and returns a message with a severity (`error`, `warning`, `info`, `style`). The tool prints findings and exits non-zero if any finding is at or above the configured **failure threshold**. Running it in a container means no installation: the program is inside the image. The Dockerfile arrives on **standard input**, shown by the `-` argument and the `<` redirect; the configuration file is mounted at `/.hadolint.yaml`, one of the places hadolint looks.

## Walkthrough of this repository's use

```yaml
# hadolint configuration. build/history/v0..v2 are teaching artifacts that exist to show what is wrong and are not linted.
failure-threshold: info
trustedRegistries:
  - docker.io
  - gcr.io
```

- `failure-threshold: info` makes even the lowest-severity "info" findings fail the check, so the Dockerfile has to be clean at every level. The default threshold would only fail on warnings and above.
- `trustedRegistries: [docker.io, gcr.io]` lists registries from which base images are accepted without a warning: Docker Hub (`golang`, `registry`) and Google's registry (`gcr.io/distroless/...`). Images from other registries would be flagged by rule `DL3026`.
- Nothing is ignored. The comment explains that the lesson's deliberately naive Dockerfiles in `scripts/measure` are not linted; they exist to show what the linter would flag (for example `DL3042`, pip without `--no-cache-dir`).

The root `Dockerfile` passes because both `FROM` lines are pinned with tag and digest (`DL3006`/`DL3007`), the last stage sets a non-root `USER` (`DL3002`), the `ENTRYPOINT` is in exec form, and each `RUN` is a single well-formed command.

## Try it yourself

1. Lint: `docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint:v2.12.0 hadolint - < Dockerfile; echo "exit $?"`. Expected: no findings, `exit 0`.
2. Lint the first recipe: `docker run --rm -i hadolint/hadolint:v2.12.0 hadolint - < build/history/v0.Dockerfile`. Expected: findings about the unpinned or missing `USER` and the `ARG`/`RUN` usage (exact codes depend on the rule set; look them up in the wiki).
3. List what a code means: look up `DL3042` in the hadolint wiki (linked below).
4. Check the version: `docker run --rm hadolint/hadolint:v2.12.0 hadolint --version`. Expected: `Haskell Dockerfile Linter 2.12.0`.

## Mistakes people make

- Silencing findings with `# hadolint ignore=` without a reason.
- Linting only on the developer's machine. CI runs the same command.
- Linting the history Dockerfiles and then "fixing" them: they exist to show the mistakes.
- Forgetting that findings inside `RUN` come from ShellCheck and follow shell rules.

## Check yourself

1. What does hadolint read? *A Dockerfile, from standard input here.*
2. What does `failure-threshold: info` mean? *Any finding, even at info level, makes the run fail.*
3. How does the config file reach the container? *It is mounted read-only at `/.hadolint.yaml`.*
4. Why are the naive Dockerfiles not linted? *They are teaching artifacts that show what is wrong.*
5. Where do `SC` codes come from? *ShellCheck, which hadolint applies to `RUN` commands.*

## Further reading

- hadolint repository and rule list (v2.12.0): <https://github.com/hadolint/hadolint/tree/v2.12.0>
- Rule wiki: <https://github.com/hadolint/hadolint/wiki>
