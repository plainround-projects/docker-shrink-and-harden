# ShellCheck 0.10

## What it is

ShellCheck is a **linter for shell scripts**. It reads a script without running it and warns about mistakes that shells accept silently: unquoted variables, commands whose failure is ignored, features that exist in Bash but not in `sh`. Every warning has a code such as `SC2086`. This repository runs `koalaman/shellcheck:v0.10.0` as a container.

## Why this repository uses it

Shell scripts fail in quiet ways. A missing quote works on every test value and breaks on the first path with a space. The template names shell scripts as code that needs a linter in CI.

## Where it appears

| Path | What it does |
| --- | --- |
| `Makefile` | `lint` runs the container over `scripts/*.sh tests/e2e/*.sh` with `--external-sources --source-path=SCRIPTDIR`. |
| `scripts/*.sh`, `tests/e2e/*.sh` | The files it checks. |

## How it works underneath

ShellCheck parses the script the way the shell named in the first line (`#!/bin/sh` or `bash`) would, then applies its rules to the syntax tree. It prints the offending line, a caret under the problem and the code. The container runs it as `shellcheck FILES`. `-v "$(CURDIR):/mnt:ro" -w /mnt` mounts the project read-only and makes it the working folder, so relative paths in messages are meaningful.

## Walkthrough of this repository's use

```makefile
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(SHELLCHECK_IMAGE) --external-sources --source-path=SCRIPTDIR scripts/*.sh tests/e2e/*.sh
```

- `-v "$(CURDIR):/mnt:ro" -w /mnt` gives the container a read-only view of the project at `/mnt` and makes it the working folder.
- `--external-sources` lets ShellCheck follow `source`d files. `--source-path=SCRIPTDIR` tells it to resolve them relative to the script's own folder. Each script has a comment such as `# shellcheck source=../../scripts/lib.sh` just above `. "$(dirname "$0")/../../scripts/lib.sh"`, because the real path is computed at run time and ShellCheck cannot guess it.
- In `lib.sh`, a few variables are `export`ed (`REGISTRY`, `BUILDER`, `TRIVY_IMAGE`): they are used by the scripts that source the library, and ShellCheck would otherwise warn `SC2034` ("appears unused") when it analyzes the file alone.
- Loops that do not use the counter use `_` (`for _ in $(seq 1 40)`) for the same reason.
- `test 01` first stored the exported file list in a command substitution inside `check ... "$( ... && ... || ...)"`, which ShellCheck flagged as `SC2015` (`A && B || C` is not an if-then-else); the code now uses separate statements.

## Try it yourself

1. Run it: `docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.10.0 --external-sources --source-path=SCRIPTDIR scripts/*.sh tests/e2e/*.sh; echo "exit $?"`. Expected: no output, `exit 0`.
2. Make a mistake: `printf '#!/bin/sh\nx="a b"\nls $x\n' > /tmp/t.sh` and run `docker run --rm -v /tmp:/mnt:ro -w /mnt koalaman/shellcheck:v0.10.0 t.sh`. Expected: `SC2086 (info): Double quote to prevent globbing and word splitting.`
3. See a Bash feature in an `sh` script: `printf '#!/bin/sh\nif [[ -n "$1" ]]; then echo hi; fi\n' > /tmp/t2.sh` and check it. Expected: `SC3010` (in POSIX sh, `[[ ]]` is undefined).
4. Read the explanation of a code at <https://www.shellcheck.net/wiki/SC2086>.

## Mistakes people make

- Ignoring warnings "because it works". It works until a value contains a space.
- Choosing `#!/bin/sh` and then using Bash-only syntax.
- Disabling a check globally instead of on the one line that needs it.

## Check yourself

1. What does SC2086 warn about? *An unquoted variable that the shell will split and expand.*
2. Why does the shebang matter to ShellCheck? *It decides which shell's rules apply.*
3. What does `-v "$(CURDIR):/mnt:ro"` do? *Gives the container a read-only view of the project at `/mnt`.*
4. Why is `fetch()` a function and not a variable? *`"$@"` passes arguments safely; an unquoted variable splits.*
5. Does ShellCheck run the script? *No. It only reads it.*

## Further reading

- ShellCheck: <https://www.shellcheck.net/> and wiki <https://www.shellcheck.net/wiki/>
- Repository (v0.10.0): <https://github.com/koalaman/shellcheck/tree/v0.10.0>
