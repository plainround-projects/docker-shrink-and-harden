# `.gitignore`, `.dockerignore` and `.editorconfig`

## What it is

Three small text files that tell tools what to skip or how to format.

- `.gitignore` tells Git which files never to track (secrets, caches, build output).
- `.dockerignore` tells `docker build` which files never to send to the builder.
- `.editorconfig` tells editors and tools basic formatting rules: line endings, indentation, trailing spaces.

## Why this repository uses it

The template says: never commit build artifacts or local state, and keep `git status` clean after the last commit. The Docker lesson says the build context should be small and must not contain `.env`. A shared `.editorconfig` keeps contributors' editors consistent.

## Where it appears

| Path | What it does |
| --- | --- |
| `.gitignore` | Ignores `/netrc`, `/svc`, `/bin/`, test and coverage output, `.env`, `.DS_Store`, `.omc/`. |
| `.dockerignore` | Excludes `.git`, `.github`, `.env*`, `netrc`, `docs`, `tests`, `scripts`, `build`, Markdown, the Makefile, the compose file and the linter settings. |
| `.editorconfig` | UTF-8, LF line endings, final newline, four spaces (two in YAML, JSON, TOML), tabs in Go files and Makefiles. |

## How it works underneath

Each file is a list of **patterns**, one per line. `*` matches any characters, `**` matches across folders, a trailing `/` matches folders, `!` negates (include again). Git reads `.gitignore` while looking for untracked files; a file already tracked is not affected until removed from the index. Docker reads `.dockerignore` before building: matching files are not sent, so `COPY` cannot copy them and changes to them do not invalidate layers. Editors that support EditorConfig search upward for `.editorconfig` and apply the `[section]` that matches the file name.

## Walkthrough of this repository's use

```text
/netrc
/svc
/bin/
*.test
*.out
coverage.out
.env
.DS_Store
.omc/
```

- `/netrc` (with the leading slash) ignores only the file at the project root: the demo credentials copied from `netrc.example`. `/svc` and `/bin/` ignore a compiled binary should one be built on the host. `*.test`, `*.out`, `coverage.out` are Go test products.
- `.env` is the settings file; `.DS_Store` is a macOS folder-view file; `.omc/` is local tooling state.

```text
.git
.github
.env
.env.*
!.env.example
netrc
docs
tests
scripts
build
*.md
Makefile
docker-compose.yml
.golangci.yml
.hadolint.yaml
```

- `netrc` and `.env*` are excluded, then `!.env.example` brings the example back (later patterns override earlier ones). Without this, `COPY . .` in the build stage would copy the credentials file into a layer.
- `docs`, `tests`, `scripts` and `build` are not needed to compile the program, so they are not sent. `*.md` skips all Markdown.

```text
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{yml,yaml,json,toml}]
indent_size = 2

[*.go]
indent_style = tab

[Makefile]
indent_style = tab

[*.md]
trim_trailing_whitespace = false
```

- `root = true` stops the search for parent files.
- `[*]` applies to every file. `end_of_line = lf` is Unix line endings; the other two lines keep diffs clean.
- `[*.go] indent_style = tab` follows `gofmt`, which indents with tabs. `[Makefile]` needs tabs because Make requires them before recipe lines.

## Try it yourself

1. See ignored files: `git status --ignored --short | head`. Expected: lines starting with `!!` for `netrc`, `.env` and similar.
2. Ask why a file is ignored: `git check-ignore -v netrc`. Expected: the matching rule, `.gitignore:1:/netrc`.
3. Check that `netrc` is not in the build context: `docker build --progress=plain --secret id=netrc,src=netrc . 2>&1 | grep -i 'transferring context'`. Expected: a small context size (kilobytes).
4. Confirm nothing is untracked: `git status --short`. Expected: no output.

## Mistakes people make

- Adding a file to `.gitignore` after committing it (Git keeps tracking it).
- Forgetting `.dockerignore`, so `.git` and `.env` enter the build.
- Windows line endings in shell scripts, which break the shebang.

## Check yourself

1. What does `!` do in an ignore file? *Re-includes something an earlier pattern excluded.*
2. Why is `netrc` in both ignore files? *Git must not track credentials and Docker must not copy them into an image layer.*
3. What does `.dockerignore` change about layer caching? *Ignored files cannot invalidate a `COPY` layer.*
4. Why a tab in the Makefile section? *Make requires tabs before recipe lines.*
5. What does `root = true` do? *Stops editors searching parent folders for more settings.*

## Further reading

- gitignore: <https://git-scm.com/docs/gitignore>
- `.dockerignore`: <https://docs.docker.com/build/concepts/context/#dockerignore-files>
- EditorConfig: <https://editorconfig.org/>
