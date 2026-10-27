# YAML

## What it is

YAML is a text format for structured data: nested lists and key-value maps, written with indentation. It is easy to read, and it is the format of Docker Compose files, GitHub Actions workflows and the hadolint settings in this repository. **Indentation is meaning**: the number of spaces decides which key belongs to which parent. Tabs are not allowed for indentation.


**Words used in this note**

- **registry**: A server that stores and serves images.
- **JSON**: A text format for data. An object is `{"name": "value"}`, a list is `[1, 2]`; values are strings, numbers, `true`, `false` or `null`.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **shell**: A program that reads the commands you type (or a script's lines) and starts other programs for you. Bash is a shell.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.

## Why this repository uses it

The tools it uses chose YAML: Compose (`docker-compose.yml`), GitHub Actions (`.github/workflows/ci.yml`), hadolint (`.hadolint.yaml`) and golangci-lint (`.golangci.yml`). You cannot read those files without knowing the few rules below.

## Where it appears

| Path | What it is |
| --- | --- |
| `docker-compose.yml` | The registry and the deployed service. |
| `.github/workflows/ci.yml` | The CI workflow. |
| `.hadolint.yaml` | Dockerfile linter settings. |
| `.golangci.yml` | Go linter settings. |

## How it works underneath

A YAML file is parsed into the same kinds of values as JSON: maps, lists, strings, numbers, booleans, null.

- `key: value` is a map entry. A nested map is an indented block under a key.
- `- item` is a list entry. `[a, b]` is a list written on one line; `{a: 1}` is a map on one line.
- Strings need no quotes, but numbers and words YAML reads specially do: `"3.12"` stays a string, while `3.12` is a number; `"1.0"` is not `1.0`. Words like `yes`, `no`, `on` and `off` could be read as booleans in YAML 1.1, so quote them when you mean text.
- `#` starts a comment.
- A multi-line string uses `|` (keep newlines) or `>` (fold them into spaces).

## Walkthrough of this repository's use

Features that appear in `docker-compose.yml`:

```yaml
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--spider", "http://127.0.0.1:5000/v2/"]
      interval: 3s
      timeout: 3s
      retries: 10
```

- `healthcheck:` is a key whose value is a map of four keys.
- `test: ["CMD", "wget", "--quiet", "--spider", "http://127.0.0.1:5000/v2/"]` is a one-line list of strings. The list form means "run this program with these arguments, no shell".
- `interval: 3s` is a string that Compose understands as a duration.

A list in block form, and a quoted string with a variable (the variable is expanded by Compose, not by YAML):

```yaml
    ports:
      # Loopback only. 5057 because macOS keeps 5000 for AirPlay Receiver.
      - "127.0.0.1:${REGISTRY_PORT:-5057}:5000"
```

- `- "..."` is a list entry. Quotes are needed: `127.0.0.1:...:5000` contains colons, which YAML could take for a map.

From `.golangci.yml`:

```yaml
linters:
  default: standard
  enable:
    - errorlint
    - gosec
    - misspell
    - revive
    - unconvert
    - bodyclose
    - noctx
    - nilerr
    - predeclared
```

- `linters:` holds a key `default` and a list `enable`; each `- name` is one entry.
- `version: "2"` is quoted so it stays text.

## Try it yourself

1. Parse a file: `uv run --no-project --with pyyaml python -c "import yaml; print(yaml.safe_load(open('.hadolint.yaml')))"` (uv fetches PyYAML for this one command). Expected: `{'failure-threshold': 'info', 'trustedRegistries': ['docker.io', 'gcr.io']}`.
2. Validate Compose syntax: `docker compose config --quiet`. Expected: no output and exit 0.
3. Break the indentation of one key in a copy of the compose file and run the same command. Expected: a parse error naming the line.
4. See the quoting trap: `uv run --no-project --with pyyaml python -c "import yaml; print(yaml.safe_load('v: 3.10'), yaml.safe_load('v: \"3.10\"'))"`. Expected: `{'v': 3.1} {'v': '3.10'}`.

## Mistakes people make

- Using tabs.
- Unquoted versions like `3.10`.
- Misaligned indentation that silently moves a key to the wrong parent.
- Forgetting that `-` makes a list entry.

## Check yourself

1. What does indentation mean in YAML? *It sets the parent-child structure.*
2. Why quote `"3.12"`? *Unquoted it is a number, and trailing zeros are lost in versions like 3.10.*
3. How do you write a list on one line? *`[a, b, c]`.*
4. Who expands `${VAR}` in `docker-compose.yml`? *Docker Compose, after parsing.*
5. What starts a comment? *`#`.*

## Further reading

- YAML 1.2 specification: <https://yaml.org/spec/1.2.2/>
- PyYAML: <https://pyyaml.org/wiki/PyYAMLDocumentation>
