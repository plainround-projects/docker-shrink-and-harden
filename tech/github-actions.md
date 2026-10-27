# GitHub Actions

## What it is

GitHub Actions is GitHub's built-in automation. Workflows are YAML files under `.github/workflows/`. On an **event** such as a push, GitHub starts a fresh virtual machine (a **runner**), checks out your code and runs your steps. The result shows as a green or red mark on the commit.

## Why this repository uses it

The template says CI runs format, lint, tests and the audit on every push, mirroring the commands a reader runs. The workflow only calls `make` targets, so CI and a laptop run the same commands.

## Where it appears

| Path | What it does |
| --- | --- |
| `.github/workflows/ci.yml` | Two jobs: `check` (lint, tests, audit) and `images` (build v0 to v4 and run every Done-when script). |

The repository has not been pushed to GitHub, so the workflow has not run there. The same commands were run locally.

## How it works underneath

A workflow has triggers under `on:` and **jobs**. Each job runs on its own runner in parallel with the others. A job is a list of **steps**: `run:` executes a shell command; `uses: owner/name@version` runs a packaged **action**. A job fails when any step exits non-zero. The `ubuntu-latest` runner has Docker, Git, `make`, `jq` and `curl` installed, which is all this repository needs: Go and its tools come from containers.

## Walkthrough of this repository's use

```yaml
name: ci

on: [push, pull_request]

jobs:
  check:
    name: gofmt, go vet, golangci-lint, hadolint, shellcheck, unit tests with coverage, govulncheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make lint
      - run: make test
      - run: make audit

  images:
    name: Build v0 to v4 and check every Done-when line against real images
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make test-e2e
```

- `on: [push, pull_request]` runs it on every push and pull request.
- `check` runs `make lint`, `make test`, `make audit`. Each pulls the pinned tool image on first use.
- `images` runs `make test-e2e`, which creates the BuildKit builder, starts the registry, and runs the six scripts under `tests/e2e/` against real images.
- `actions/checkout@v4` copies the repository into the runner; without it the folder is empty.

## Try it yourself

1. Check the YAML parses: `uv run --no-project --with pyyaml python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"`. Expected: `ok`.
2. Run the same commands: `make lint && make test && make audit`. Expected: all succeed.
3. After pushing to GitHub, open the repository's **Actions** tab. Expected: one run per push with two jobs.

## Mistakes people make

- CI commands that differ from local ones. Here CI only calls `make`.
- Unpinned actions (`@main`); this file uses `@v4`.
- Secrets in the YAML; none are needed.
- Forgetting the checkout step.

## Check yourself

1. What triggers this workflow? *A push or a pull request.*
2. What is a runner? *The virtual machine GitHub starts for a job.*
3. Why does the runner need no Go? *Go runs inside a pinned container.*
4. Why only `make` targets? *Identical commands everywhere.*
5. What fails a job? *Any step exiting non-zero.*

## Further reading

- GitHub Actions: <https://docs.github.com/en/actions>
- Workflow syntax: <https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions>
- `actions/checkout`: <https://github.com/actions/checkout>
