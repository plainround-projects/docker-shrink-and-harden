# curl

## What it is

curl is a command-line program that sends a request over a network protocol and prints the response. Most often the protocol is HTTP. It is installed on macOS and most Linux systems.


**Words used in this note**

- **HTTP**: The request-and-answer language of the web. A client sends a request (a method such as GET or POST, a path, optional headers and a body). The server answers with a status code (200 OK, 404 not found, 500 server error) and a body.
- **localhost**: The address that always means 'this same computer'. `127.0.0.1` is its numeric form.
- **image**: A read-only bundle of files and settings from which containers are started.
- **container**: A process (or a group of processes) run in isolation, with its own view of files, network and process list, but sharing the host's kernel.
- **port**: A number from 1 to 65535 that says which program on a computer should receive a network connection. A web server listens on a port such as 8080; you reach it as `host:port`.
- **JSON**: A text format for data. An object is `{"name": "value"}`, a list is `[1, 2]`; values are strings, numbers, `true`, `false` or `null`.
- **shell**: A program that reads the commands you type (or a script's lines) and starts other programs for you. Bash is a shell.

## Why this repository uses it

The lesson's smoke test is `curl localhost:8080/health`. The scripts use it to prove each image works: start it, fetch `/health` or `/version`, compare the answer.

## Where it appears

| Path | What it does |
| --- | --- |
| `scripts/lib.sh` (`serve_and_get`) | Fetches a path from a container just started, retrying until it answers. |
| `scripts/deploy.sh` | Calls `/health` and `/version` on the deployed service. |
| `tests/e2e/02_...`, `04_...`, `05_...` | Smoke tests through `serve_and_get`. |

## How it works underneath

curl opens a TCP connection to the host and port in the URL, writes an HTTP request (a method, a path, headers, optionally a body), reads the response (a status line, headers, a body) and prints the body. The **status code** is a three-digit number: 2xx success, 4xx the client was wrong, 5xx the server failed. By default curl exits 0 even for a 404 or 503, because the transfer worked; `-f` changes that.

## Walkthrough of this repository's use

```bash
serve_and_get() {
  local name="svc-smoke-$$"
  CLEANUP_CONTAINERS+=("${name}")
  docker run -d --name "${name}" -p "127.0.0.1:$2:8080" "$1" > /dev/null
  local body=""
  for _ in $(seq 1 40); do
    body="$(curl -fsS "http://127.0.0.1:$2$3" 2> /dev/null)" && break
    sleep 0.25
  done
  docker rm -f "${name}" > /dev/null
  printf '%s' "${body}"
}
```

- `-p 127.0.0.1:$2:8080` (in the `docker run` line) publishes the container's port 8080 on the host's loopback at the port you chose.
- `curl -fsS "http://127.0.0.1:$2$3"` builds the URL from the port and path arguments. `-f` fails on HTTP errors, `-s` hides the progress bar, `-S` still shows an error message.
- `2> /dev/null` drops curl's error text during the retries, because a connection refused while the container starts is expected. The loop tries up to 40 times, 0.25 s apart.

And in the deploy script:

```bash
port="${SVC_PORT:-8089}"
echo "GET /health  -> $(curl -fsS "http://127.0.0.1:${port}/health")"
echo "GET /version -> $(curl -fsS "http://127.0.0.1:${port}/version")"
echo "user         -> $(docker inspect --format '{{.Config.User}}' "$(docker compose --profile deploy ps -q svc)")"
echo "health       -> $(docker inspect --format '{{.State.Health.Status}}' "$(docker compose --profile deploy ps -q svc)")"
```

`curl -fsS` fetches `/health` (answer `ok`) and `/version` (answer `{"version":"v3","commit":"...","goVersion":"go1.26.10"}`), printed inside `echo "..."`.

## Try it yourself

1. After `make run`: `curl -s localhost:8089/health`. Expected: `ok`.
2. `curl -s localhost:8089/version`. Expected: JSON with `version`, `commit`, `goVersion`.
3. Status and headers: `curl -si localhost:8089/health`. Expected: `HTTP/1.1 200 OK`.
4. Wrong method: `curl -si -X POST localhost:8089/health`. Expected: `HTTP/1.1 405 Method Not Allowed`.
5. Unknown path: `curl -s -o /dev/null -w '%{http_code}\n' localhost:8089/nope`. Expected: `404`.

## Mistakes people make

- Forgetting `-f` in scripts, so a 500 looks like success.
- Testing before the server is ready; the loop retries.
- Quoting URLs with `&` or `?` in a shell without quotes.

## Check yourself

1. What does `-f` change? *HTTP errors (400 and above) make curl exit non-zero.*
2. Why a retry loop? *The container needs a moment before it answers.*
3. What does `-s` hide? *The progress meter.*
4. What does a 405 mean? *The path exists but not for that method.*
5. What does `-p 127.0.0.1:18081:8080` do? *Publishes container port 8080 on the host's loopback port 18081.*

## Further reading

- curl documentation: <https://curl.se/docs/>
- Command-line options: <https://curl.se/docs/manpage.html>
- HTTP status codes: <https://developer.mozilla.org/en-US/docs/Web/HTTP/Status>
