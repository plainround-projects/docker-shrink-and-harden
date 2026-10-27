# 4. Pin base images by digest; deploy the service by digest

Status: accepted, 2026-10-27

## Context

A tag can be moved to a different image, so the same name can mean different code on different days. Step 5 asks for the test: retag `latest` and show the deploy command does not change.

## Decision

Every `FROM` carries `tag@sha256:digest`: the tag for people, the digest for the build. The Compose file's deploy service takes `SVC_IMAGE` as a digest reference and refuses to start without it; `scripts/deploy.sh` pushes, reads the digest from the push output and deploys `localhost:5057/svc@sha256:...`. `tests/e2e/05_digest_pinning.sh` pushes v3, pushes a different image under the same tag, and shows the digest reference still runs the first.

## Alternatives considered

- **Pin only the runtime base:** the build stage's compiler is also an input to the binary.
- **Tags only, with a policy not to move them:** a policy is not a fingerprint.

## Consequences

- Pinned digests do not update themselves. A bot (Renovate or Dependabot) opens a pull request when a new digest appears, so pinning does not freeze the project; the README says so.
- The local registry listens on 5057 because macOS keeps 5000 for AirPlay Receiver.
