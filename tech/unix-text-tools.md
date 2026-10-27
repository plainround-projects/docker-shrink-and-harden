# Small Unix text tools: grep, sed, awk, tr, cut, tar, sort, perl

## What it is

Unix programs that each do one small job on text, and are joined with pipes (`a | b`). Every one of them appears in this repository's scripts.

- **grep** prints lines that match a pattern (`-c` counts them, `-q` is silent and only sets the exit code, `-E` allows extended patterns, `-i` ignores case, `-m1` stops at the first match).
- **sed** edits a stream of text. `sed -n 's/old/new/p'` substitutes and prints only changed lines.
- **awk** is a tiny programming language for columns and arithmetic.
- **tr** replaces or deletes characters. **cut** takes columns. **sort** orders lines. **head/tail** take the first/last lines. **tar** packs and unpacks folders into one stream.
- **perl** is a scripting language; here a one-liner prints the time with sub-second precision.

## Why this repository uses it

The scripts read tool output and numbers: the digest after `docker push`, the percentage after `go test -cover`, the seconds a build took. These tools turn text into values.

## Where it appears

| Path | What it does |
| --- | --- |
| `scripts/deploy.sh`, `tests/e2e/05_digest_pinning.sh` | `sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p'` extracts the digest from `docker push` output. |
| `scripts/coverage.sh` | `sed` pulls the coverage percentage; `awk` compares it with 95. |
| `scripts/lib.sh` | `awk` for arithmetic and rounding; `perl` for time; `sed` to read step numbers. |
| `tests/e2e/03_warm_build_uses_the_cache.sh`, `scripts/measure.sh` | `tar --exclude=.git -cf - . \| tar -xf - -C DIR` copies the project into a scratch folder. |
| `tests/e2e/01_...sh` | `docker export ... \| tar -t \| grep -c netrc` lists an image's files and counts matches. |
| `Makefile` | `help` target: `grep -E` then `sed -E` then `sort` to print the menu. |

## How it works underneath

Each program reads **standard input** and writes **standard output**; the pipe connects one's output to the next one's input. They work line by line, so they handle huge outputs with little memory. `sed`'s `s/pattern/replacement/flags` uses **regular expressions**: `.` any character, `*` repeat, `[0-9a-f]` a character from a set, `\( ... \)` a group that `\1` repeats in the replacement. `awk` splits each line into fields (`$1`, `$2`) and can run code in a `BEGIN { ... }` block without reading any input.

## Walkthrough of this repository's use

### The digest

```bash
digest="$(docker push "${REGISTRY}/svc:v3" | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' | tail -1)"
echo "pushed ${REGISTRY}/svc:v3 as ${digest}"
```

`docker push` prints a line such as `v3: digest: sha256:31b09ac7... size: 2417`. The `sed` expression `s/.*digest: \(sha256:[0-9a-f]*\).*/\1/p`: match everything up to `digest: `, remember the `sha256:` followed by any run of hex digits, match the rest, and print only the remembered part. `-n` suppresses lines that did not match. `tail -1` keeps the last such line.

### Coverage gate

```bash
  percent="$(echo "${output}" | sed -n 's/.*coverage: \([0-9.]*\)%.*/\1/p')"
  if awk -v p="${percent}" 'BEGIN { exit !(p >= 95) }'; then
    echo "coverage of internal/${package}: ${percent}% (needs 95%)"
  else
    echo "coverage of internal/${package}: ${percent:-none}% is below 95%"
    status=1
  fi
```

`sed -n 's/.*coverage: \([0-9.]*\)%.*/\1/p'` keeps the number between `coverage: ` and `%`. `awk -v p="${percent}" 'BEGIN { exit !(p >= 95) }'` sets awk variable `p`, then in the `BEGIN` block exits with a code. A true comparison is 1; `!` turns it into 0, and exit code 0 means success to the shell. So the command succeeds exactly when the percentage is at least 95.

### Time and arithmetic

```bash
seconds_of() { # seconds_of <command...>: run quietly, print elapsed wall-clock seconds with two decimals
  local start end
  start="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  "$@" > /dev/null 2>&1
  end="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  awk -v s="${start}" -v e="${end}" 'BEGIN { printf "%.2f", e - s }'
}
```

`perl -MTime::HiRes=time -e 'printf "%.3f", time'` loads the high-resolution `time` function and prints seconds with three decimals. `awk -v s=... -v e=... 'BEGIN { printf "%.2f", e - s }'` subtracts and prints two decimals. The shell cannot do decimal arithmetic itself.

### Copying a project without `.git`

```bash
tar --exclude=.git --exclude=docs -cf - . | tar -xf - -C "${WORK}"
```

The first `tar` writes an archive of the current folder to standard output (`-cf -`), leaving out `.git` and `docs`; the second reads it from standard input (`-xf -`) and unpacks it into the scratch folder (`-C`). It is a copy that skips what you exclude.

## Try it yourself

1. Extract a digest: `echo 'v3: digest: sha256:abc123 size: 527' | sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p'`. Expected: `sha256:abc123`.
2. Count matches: `printf 'a\nb\na\n' | grep -c a`. Expected: `2`.
3. Compare numbers: `awk -v p=97.5 'BEGIN { exit !(p >= 95) }'; echo $?`. Expected: `0`.
4. Subtract: `awk -v s=1.25 -v e=3.5 'BEGIN { printf "%.2f\n", e - s }'`. Expected: `2.25`.
5. Replace characters: `printf 'a\0b\0' | tr '\0' ' '`. Expected: `a b `.

## Mistakes people make

- Parsing output meant for people. Prefer `--format` flags, as the scripts do when the tool offers them.
- Forgetting `-n` with `sed ... p`, which prints every line twice.
- Different flags on macOS (BSD) and Linux (GNU) versions of `sed`, `date`, `tar`. The scripts use only options both share.
- Treating regular expressions as globs: `*` means different things in each.

## Check yourself

1. What does a pipe do? *Connects one program's output to the next one's input.*
2. What does `sed -n 's/x/y/p'` print? *Only the lines where a substitution happened.*
3. How does `awk 'BEGIN { exit !(p >= 95) }'` signal success? *It exits 0 when the comparison is true.*
4. Why `perl` for the clock? *macOS `date` has no sub-second option.*
5. What does `tar -cf - . | tar -xf - -C dir` do? *Copies a folder tree to `dir`.*

## Further reading

- GNU grep manual: <https://www.gnu.org/software/grep/manual/grep.html>
- GNU sed manual: <https://www.gnu.org/software/sed/manual/sed.html>
- The AWK Programming Language / GNU awk manual: <https://www.gnu.org/software/gawk/manual/gawk.html>
- POSIX utilities: <https://pubs.opengroup.org/onlinepubs/9699919799/idx/utilities.html>
