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
