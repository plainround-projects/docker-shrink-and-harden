# jq

## What it is

jq is a command-line tool for reading and reshaping **JSON**. JSON is a text format for structured data: objects `{"key": value}`, lists `[1, 2]`, strings, numbers, `true`, `false`, `null`. jq takes JSON on standard input and a **filter** (a small expression) and prints the result. Think of it as `grep` and `sed` for JSON.

## Why this repository uses it

Docker, Trivy and BuildKit all print JSON. The scripts use jq to pull out one number or one list: the scanner's critical and high counts, the packages of an SBOM, the provenance inputs.

## Where it appears

| Path | What it does with jq |
| --- | --- |
| `scripts/lib.sh` (`high_critical`) | Counts critical and high findings in Trivy's JSON. |
| `scripts/sbom.sh` | Lists SBOM packages and provenance inputs. |
| `tests/e2e/05_digest_pinning.sh`, `06_sbom_and_provenance.sh` | Read `/version` output; assert facts about the SBOM. |

## How it works underneath

A jq filter is applied to each JSON value that arrives. `.` is the value itself, `.name` an object's field, `.[]` every element of a list or object, `|` feeds the result of the left side into the right. `select(condition)` keeps only items for which the condition is true. `[ ... ]` collects results into a list, `map(f)` applies f to each element, `length` counts. `-r` prints strings without quotes. A trailing `?` (as in `.Results[]?`) ignores errors when a key is missing.

## Walkthrough of this repository's use

```bash
# high_critical <image>: the scanner's count of critical and high vulnerabilities as "critical/high".
high_critical() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v shrink-trivy-cache:/root/.cache/ "${TRIVY_IMAGE}" \
    image --quiet --scanners vuln --format json "$1" 2> /dev/null \
    | jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | "\(map(select(. == "CRITICAL")) | length)/\(map(select(. == "HIGH")) | length)"'
}
```

Read the jq filter from left to right:

- `[.Results[]?.Vulnerabilities[]?.Severity]`: for every entry of `Results`, for every entry of its `Vulnerabilities`, take the `Severity` text, and collect them in a list such as `["HIGH","HIGH","CRITICAL"]`. The `?` makes images with no findings produce an empty list instead of an error.
- `| "\(map(select(. == "CRITICAL")) | length)/\(map(select(. == "HIGH")) | length)"`: build a string. Inside `\( ... )`, `map(select(. == "CRITICAL"))` keeps only the critical entries and `length` counts them; the same for `"HIGH"`. The two numbers are joined by `/`, giving `7/290` for v0.

From the SBOM script:

```bash
docker buildx imagetools inspect "${REGISTRY}/svc:v4" --format '{{ json .SBOM }}' | jq -r '.SPDX.packages[] | select(.versionInfo != null) | "\(.name) \(.versionInfo)"' | sort
```

(`select(.versionInfo != null)` skips the SPDX document's own pseudo-entry, which has no version.)

From a test:

```bash
check "the digest deploy still runs the first image" "$(echo "${by_digest}" | jq -r .version)" v3
check "the moved tag runs the other image" "$(echo "${by_tag}" | jq -r .version)" other
```

`jq -r .version` prints the `version` field without quotes, so the test can compare it with `v3` and `other`.

## Try it yourself

1. Pretty-print: `echo '{"a":[1,2,3]}' | jq .`. Expected: the JSON indented over several lines.
2. Pick a field: `curl -s localhost:8089/version | jq -r .goVersion`. Expected: `go1.26.10`.
3. Count with a filter: `echo '["HIGH","LOW","HIGH"]' | jq 'map(select(. == "HIGH")) | length'`. Expected: `2`.
4. Try the optional operator: `echo '{}' | jq '[.Results[]?.x]'`. Expected: `[]`.

## Mistakes people make

- Forgetting `-r` and getting quoted strings.
- Using `.[]` on `null` (it errors) instead of `.[]?`.
- Quoting: wrap the filter in single quotes so the shell leaves `$`, `|` and `"` alone.

## Check yourself

1. What does `.[]` do? *Produces every element of a list or every value of an object.*
2. What does `-r` do? *Prints raw strings without quotes.*
3. What does `?` after an expression do? *Suppresses the error if it does not apply (e.g. a missing key).*
4. What is `select` for? *Keeping only items that satisfy a condition.*
5. How does the script count critical findings? *It collects severities into a list, filters `CRITICAL` and takes `length`.*

## Further reading

- jq manual: <https://jqlang.github.io/jq/manual/>
- jq tutorial: <https://jqlang.github.io/jq/tutorial/>
