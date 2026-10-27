# Trivy (vulnerability scanner)

## What it is

Trivy is a free **vulnerability scanner** from Aqua Security. Given a container image it lists the operating-system packages and the programs inside (for a Go binary it reads the Go version and modules built into it), looks each up in vulnerability databases, and prints known problems with a severity: LOW, MEDIUM, HIGH, CRITICAL. This repository runs the container `aquasec/trivy:0.58.0`.

## Why this repository uses it

The lesson wants a "vulnerability count" for every image version: it should fall as the image shrinks. The lesson names Docker Scout or Trivy. Docker Scout needs a Docker account, so this repository uses Trivy.

## Where it appears

| Path | What it does |
| --- | --- |
| `scripts/lib.sh` (`high_critical`) | Runs Trivy on an image and prints `critical/high`. |
| `scripts/measure.sh` | Records the counts per version. |
| `tests/e2e/04_distroless_nonroot_fewer_findings.sh` | Asserts v3's count is not above v1's. |

## How it works underneath

Trivy downloads its **vulnerability database** (about 70 MB, cached in a volume) and then scans offline. It reads the image through the Docker socket (`/var/run/docker.sock`), unpacks the layers and finds packages from the package manager files (`/var/lib/dpkg/status` on Debian), and from the Go binary's embedded build information. A finding links a package version to an advisory that says "fixed in X". The count therefore depends on both the image and the database of the day.

## Walkthrough of this repository's use

```bash
# high_critical <image>: the scanner's count of critical and high vulnerabilities as "critical/high".
high_critical() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v shrink-trivy-cache:/root/.cache/ "${TRIVY_IMAGE}" \
    image --quiet --scanners vuln --format json "$1" 2> /dev/null \
    | jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | "\(map(select(. == "CRITICAL")) | length)/\(map(select(. == "HIGH")) | length)"'
}
```

- `-v /var/run/docker.sock:/var/run/docker.sock` lets the Trivy container ask the host's Docker engine for the image (an image loaded with `--load`, not in a registry).
- `-v shrink-trivy-cache:/root/.cache/` keeps the database between runs.
- `image --quiet --scanners vuln --format json svc:v1` scans for vulnerabilities only and prints JSON, with progress messages hidden.
- `jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | ...'` collects every finding's severity into one list and builds the string `critical/high` by counting `"CRITICAL"` and `"HIGH"` entries. The `?` after `[]` means "skip if the key is missing" (an image with no findings has no `Vulnerabilities` key).

Results measured here (Trivy 0.58.0, database of 2026-10-27):

| Image | Critical / high |
| --- | --- |
| v0, the full SDK image | 7 / 290 |
| v1, v2 (Debian slim runtime) | 1 / 56 |
| v3, v4 (distroless static) | 0 / 0 |

## Try it yourself

1. Scan one image: `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.58.0 image --severity CRITICAL,HIGH svc:v1`. Expected: a table of packages with `CVE` ids (the first run downloads the database).
2. Count like the script: `. scripts/lib.sh; high_critical svc:v3` in a Bash shell. Expected: `0/0`.
3. Compare v0 and v3 after `make measure`: `docker image ls svc`, then scan each. Expected: a large drop.
4. See which package carries a finding: add `--format json` and open the output in `jq`.

## Mistakes people make

- Treating the absolute number as fixed. It changes daily with the database.
- Scanning only once, at build time. New advisories appear later.
- Counting findings in packages the program never uses as equal to exploitable ones.

## Check yourself

1. What does Trivy compare? *The packages and binaries in an image against vulnerability databases.*
2. Why does the count change over time? *The database gains new advisories.*
3. Why mount the Docker socket? *So Trivy can read a local image that is not in a registry.*
4. Why did v3 drop to zero? *The distroless static image has almost no packages, and the Go 1.26 standard library has no known flaws.*
5. Why not Docker Scout? *It needs a Docker account.*

## Further reading

- Trivy documentation (0.58): <https://aquasecurity.github.io/trivy/v0.58/>
- Container image scanning: <https://aquasecurity.github.io/trivy/v0.58/docs/target/container_image/>
