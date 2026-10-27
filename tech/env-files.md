# Environment variables and `.env` files

## What it is

An **environment variable** is a named piece of text that the operating system passes to every program it starts, for example `SVC_PORT=8089`. A **`.env` file** is a plain text file of `NAME=value` lines that tools such as Docker Compose and Make load for you.

## Why this repository uses it

The template says configuration comes from the environment and `.env.example` lists every variable with no real secret. The service itself reads three variables (`PORT`, `LOG_LEVEL`, `SHUTDOWN_TIMEOUT_SECONDS`); the Makefile and compose file read three more.

## Where it appears

| Path | What it does |
| --- | --- |
| `.env.example` | Committed template: the demo token, the registry port, the service port. |
| `.env` | Not committed; `make up` creates it from the example. |
| `Makefile` | `-include .env` and `export` give recipes the values. |
| `docker-compose.yml` | Reads `.env` for `${REGISTRY_PORT:-5057}` and `${SVC_PORT:-8089}`. |
| `scripts/lib.sh` | Sources `.env` to learn `REGISTRY_PORT` and `PKG_TOKEN`. |
| `internal/infrastructure/config/config.go` | The Go program's own settings. |

## How it works underneath

Compose reads `.env` from the project folder to fill `${NAME}` in the compose file. Make's `-include .env` reads it as Makefile syntax (lines of `NAME=value`), and `export` hands every variable to the commands it runs. The Bash helper library reads it with `.` (source). A variable already set in your shell is not overridden by Make's `.env`-set values in all cases, so check the effective value when something looks wrong.

Inside the Go program, `os.Getenv("PORT")` returns the value or an empty string.

## Walkthrough of this repository's use

```text
# Copy to .env (cp .env.example .env). Every value here is made up; nothing in this project contacts the host below.
# The demo token for the pretend private package server. It is the value in netrc.example.
PKG_TOKEN=demo-token-123
# Host port of the local registry. 5000 is taken by AirPlay Receiver on macOS, so the default is 5057.
REGISTRY_PORT=5057
# Host port of the deployed service.
SVC_PORT=8089
```

- `PKG_TOKEN=demo-token-123` is the made-up token from the lesson. The scripts pass it to the v0 build as a build argument (to show the leak) and the netrc file carries the same value for the secret mount.
- `REGISTRY_PORT=5057` and `SVC_PORT=8089` set the published ports.

How the program reads its settings:

```go
// Load reads PORT (default 8080), LOG_LEVEL (default info) and SHUTDOWN_TIMEOUT_SECONDS (default 8) through getenv.
func Load(getenv func(string) string) (Config, error) {
	port, err := integer(getenv, "PORT", 8080, 1, 65535)
	if err != nil {
		return Config{}, err
	}
	seconds, err := integer(getenv, "SHUTDOWN_TIMEOUT_SECONDS", 8, 1, 60)
	if err != nil {
		return Config{}, err
	}
	level := slog.LevelInfo
	if raw := getenv("LOG_LEVEL"); raw != "" {
		if err := level.UnmarshalText([]byte(raw)); err != nil {
			return Config{}, fmt.Errorf("LOG_LEVEL must be debug, info, warn or error, got %q", raw)
		}
	}
	return Config{
		Addr:            ":" + strconv.Itoa(port),
		LogLevel:        level,
		ShutdownTimeout: time.Duration(seconds) * time.Second,
	}, nil
}

func integer(getenv func(string) string, name string, fallback, minimum, maximum int) (int, error) {
```

- `Load(getenv func(string) string)` takes the lookup function as a parameter. In production it is `os.Getenv`; in tests it is a function over a map, so tests need no real environment.
- Each setting has a default, a range (`PORT` 1 to 65535, `SHUTDOWN_TIMEOUT_SECONDS` 1 to 60) and an error that names the variable.
- `LOG_LEVEL` is parsed by `slog.Level.UnmarshalText`, which accepts `debug`, `info`, `warn`, `error`.

## Try it yourself

1. Create `.env`: `make up`, then `git status --short`. Expected: `.env` does not appear (ignored).
2. See the effective values: `docker compose config | grep -E 'published|image:'`. Expected: the port 5057 and the registry image.
3. Try a bad value: `docker run --rm -e PORT=abc localhost:5057/svc:v3`. Expected: `configuration error: PORT must be an integer, got "abc"` and exit code 2.
4. Change the log level: `docker run --rm -e LOG_LEVEL=debug -p 8080:8080 localhost:5057/svc:v3`. Expected: the service starts and logs at debug level.

## Mistakes people make

- Committing `.env` with a real secret (only the example is committed).
- Mixing up Make variables and environment variables.
- Reading the environment all over the code instead of once at start-up.

## Check yourself

1. What is an environment variable? *A named text value the OS passes to each process it starts.*
2. Why does `Load` take a function? *Tests can supply values without touching the real environment.*
3. What does the program do with `PORT=abc`? *Refuses to start with a clear message and exit code 2.*
4. Why is the example token safe? *It is made up and nothing contacts the host it is for.*
5. Which file is committed, `.env` or `.env.example`? *`.env.example`.*

## Further reading

- The Twelve-Factor App, config: <https://12factor.net/config>
- Compose environment variables: <https://docs.docker.com/compose/how-tos/environment-variables/>
- Package `os`: <https://pkg.go.dev/os@go1.26#Getenv>
