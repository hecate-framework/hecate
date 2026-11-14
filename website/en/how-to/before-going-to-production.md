---
description: A checklist of what to verify before you deploy a hecate application - environment, logging and redaction, secrets, error details, the access log, listening and limits, workers and shutdown.
hecate: "0.x"
lua: "5.5"
order: 15
---

# Before going to production

This guide is a checklist to go through before you deploy an application built with `hecate.kernel`. It is written for
hecate 0.x and Lua 5.5.

Each item names the [configuration](../reference/glossary.md#configuration) key or the option that controls it, and
its default. Most defaults are already the safe choice. The list tells you which ones are, and which ones you must set
yourself.

## Keys and options

A *key* is read from the configuration, which merges files, environment variables and secret files. The application
applies it when you write `Application({ configuration = configuration })`. An explicit option of `Application` wins
over its key.

Some settings are *options* only, with no key and no environment variable. The items say so.

How the layers, the files and the environment variables combine is in
[Configure an application](configure-an-application.md).

## The environment

- [ ] **The environment is `production`.** The [environment](../reference/glossary.md#configuration) names the
  deployment profile. It is the `environment` option of `config.load`, else `HECATE_ENV`, else `production`.
  - A process that is told nothing runs as production.
  - Check that no deployment script, image or `.env` file sets `HECATE_ENV=development` or `HECATE_ENV=test`.
  - To fail fast, check `configuration:environment() == "production"` in your entry point.
- [ ] **`config/production.lua` keeps the development settings out.** The development and test values belong in
  `config/development.lua` and `config/test.lua` only. They are `errors.expose_details = true`,
  `requests.inputs = "lax"` and a low `server.grace_timeout`. Never put them in `config/default.lua`, which every
  environment reads.
- [ ] **Response validation is off, or on by choice.** The `validate_responses` option has no key. It defaults to
  `true` when the environment of the configuration is `development` or `test`, and to `false` otherwise. Turn it on in
  production only if you accept its cost on every response.

## Error details

- [ ] **`errors.expose_details` is `false`.** This is the default (`HECATE_ERRORS__EXPOSE_DETAILS`). When it is `true`,
  the answers carry more:
  - a 422 entry carries the message of each violation;
  - a 500 carries the extension member `debug`: the error class, the message and, when the error object holds one, its
    traceback. For a plain Lua error, the message includes the source file and line.
  - `debug.message` holds the message of the error and of each of its causes. So the text of a wrapped driver error
    reaches the client too.
- [ ] **Do not rely on the boot warning alone.** When `errors.expose_details` is `true`, the application logs a
  `warning` with code `expose_details_in_production` at boot. It does so only when a `configuration` is given and its
  environment is exactly `production`.
  - An environment named `staging` gives no warning.
  - `expose_details = true` passed as an option, without a configuration, gives no warning.
  - Fail the deployment if the record appears.
- [ ] **`requests.inputs` is `strict`.** This is the default (`HECATE_REQUESTS__INPUTS`). A request that carries an
  undeclared query parameter is refused with a 422 that names each one, never its value. So a client learns about a
  misspelt parameter at once.

## Logging

### Load the configuration so that secrets are recognised

- [ ] **Load the configuration with `kernel.load_configuration`**, not `config.load` directly. It passes
  `hecate.log.Secret` as the `wrap_secret` option, so every logging sink renders a secret key as `[redacted]`.
  - `config.load` alone does the same only when `hecate.log` is already loaded.
  - Otherwise it uses its own class. That class prints `[redacted]` through `tostring`, but a sink does not recognise it
    as a secret.

### Build the logger from the configuration

- [ ] **Let the configuration build the logger.** An explicit `logger` option of `Application` replaces the logger
  built from the `logging.*` keys. So none of them applies, `logging.redact` included. Give such a logger its own
  `redact` list.
- [ ] **Choose the severity.** `logging.severity` defaults to `informational` (`HECATE_LOGGING__SEVERITY`).
  - The names are the eight severities of RFC 5424, `emergency` to `debug`. There is no `info`.
  - `debug` in production records far more than you need.
  - `logging.severities` gives one logger a severity of its own, matched exactly against its name. The logger that the
    configuration builds is named `hecate`.
- [ ] **Choose the sinks.** `logging.sinks` defaults to `{ "console" }`.
  - `console` writes human-readable lines on the standard output.
  - `json_lines` writes one JSON object per line, still on the standard output. Use it when a platform collects the
    logs.
  - `file` needs `logging.file.path`.
- [ ] **Know what `logging.async` loses.** Set `logging.async = true` to wrap each sink in an `AsyncSink`, when a sink
  is slow and must not hold up a request. Each `AsyncSink` queues at most 1024 records. Past that, it drops records
  silently. The sink counts them, but the logger built from the configuration gives no access to that count.
- [ ] **Own the permissions and the retention of the log file.** The `file` sink opens its file for appending. The file
  gets the permissions that the umask of the process leaves. The sink never rotates the file. Set the umask, the
  permissions of the directory and the retention yourself.

### Know what the framework records

At `informational` and above, the framework logs the following.

| Event | Severity | Fields and notes |
|---|---|---|
| the listening address | `informational` | |
| the workers started and reloaded | `notice` | |
| the signals received | `notice` | |
| a warning of the container | `warning` | with its code |
| an unhandled error of an action: "unhandled error while serving a request" | `error` | see below |
| an error the client caused: "request refused" | `warning` | the same fields |
| an action that fails in a way the kernel does not answer itself, such as an expired deadline: "http.Server: the action failed" | `error` | the method, the path without the query and the error |
| a failed TLS handshake | `warning` | the address of the peer (behind a proxy, the proxy's address) |
| accept failures, and connections a worker could not take | `warning` | |

An unhandled error and a refused request carry the method, the path **without** the query, the error class, its code,
its message and the traceback.

- [ ] **Know what the traceback names.** While `errors.expose_details` is `false`, the `traceback` field names each
  cause of the error by its class and code only, for example `caused by: hecate.postgresql.QueryError (23505)`. It
  never gives the message of a cause. With the key `true`, which is the case in development and test, it carries the
  message of each cause too. So a wrapped driver error brings its text into the logs.
- [ ] **Know what the `pointer` field holds.** With `errors.expose_details` `true`, an error that carries violations (a
  failed `check`) also logs the JSON Pointer of the first one, in the `pointer` field. That pointer can hold a key the
  client sent. No message ever names it.

Some answers are **not** logged:

- an input that the kernel refuses (422, 400 for content that is not JSON, 415): the kernel returns it, it does not
  raise it;
- a problem with a status below 500 that an action returns or raises;
- the requests that the server refuses before any action runs (400, 408, 413, 414, 417, 431, 501).

Only an access log sees them. The peer address is personal data in some jurisdictions: decide how long the records are
kept.

### Keep sensitive data out of the records

- [ ] **Keep personal data out of paths.** The logged `path` drops the query, but not the path parameters. A route such
  as `/users/{email}` writes the email address into every record of a failed request.
- [ ] **Never log the argument of `on_error` whole.** The `on_error` option of `server` receives the error object
  itself, with its context and its causes. A connection string or a driver message can be in them. Record its class
  and its code instead.

## Secrets

- [ ] **Every secret key is listed in `secrets`.** Pass the dotted paths of the leaves to `kernel.load_configuration`,
  for example `secrets = { "database.password", "session.signing_key" }`.
  - A listed key is wrapped after validation. `tostring` gives `[redacted]`, and only `reveal()` gives the value.
  - An unknown path is an `ArgumentError` at load, so a typo cannot leave a key unprotected.
  - A key that is not listed is an ordinary string. `describe()`, the logs and any message the application builds with
    it print it in full.
  - The validation errors of `config.load` never quote a value, listed or not.
  - Once every secret key is listed, `configuration:describe()` is safe to log at boot.
- [ ] **Secrets come from secret files**, or else from environment variables, never from a file of the repository. A
  [secret file](../reference/glossary.md#configuration) is read in one of two ways.
  - The file named by `<NAME>_FILE`, for example `HECATE_DATABASE__PASSWORD_FILE`.
  - Else `<secrets_directory>/<NAME>`, when the `secrets_directory` option is set, as a Docker or Kubernetes secret is
    mounted.

  A secret file wins over the environment variable. Prefer files: child processes inherit the environment, and on Linux
  `/proc/<pid>/environ` shows it.
- [ ] **Call `reveal()` at the last moment**, where the value is used (the driver, the signing function). Never store
  the revealed value in a field of a record or an error.

## Redaction does not read free text

The logger redacts by **field name**, never by scanning text. This is the item that is easiest to get wrong.

- [ ] **`logging.redact` lists the names of your own sensitive fields** (`HECATE_LOGGING__REDACT`, comma separated). The
  names are added to `log.DEFAULT_REDACT`, the built-in list, which is never replaced. The built-in list holds
  `password`, `secret`, `token`, `api_key`, `authorization`, `cookie`, `session` and others. Names are matched exactly,
  case-insensitively: `user_pin` does not match `pin`.
- [ ] **Names are matched in plain tables only.** A field nested in a plain table is redacted at any depth, up to 16
  levels: `{ headers = { authorization = token } }` is safe. An object with a metatable, such as `request.fields`, is
  not inspected, and the `json_lines` sink writes it as it is. Copy the fields you need into a plain table instead.
- [ ] **No secret is ever written into a message or an error message.** `logger:error("login failed for " .. password)`
  records the password. So does `error("cannot connect with " .. dsn)`: the message of an unhandled error is a field of
  the record, and the client receives it too when `errors.expose_details` is `true`. Put values in named fields, or
  better leave them out: `logger:warning("login failed", { user = id })`.

## The access log

The framework writes no access log of its own. If you want one, pass an `on_response` hook in the `server` option of
`Application`.

The hook receives, once per response:

- the method and the `target`;
- the status and the bytes sent;
- the duration;
- `failed`: the response was not sent completely;
- `refused`: the server answered before any action ran.

- [ ] **Strip the query from `target` before you record it.** `target` is the request target as received, query
  included. A query string can carry a token (`?access_token=...`), an email address or a reset code. Record the part
  before `?`, as the records of the framework do. Or record only the query parameters you know to be harmless.
- [ ] **Do not record request headers or content.** The redaction list matches field names. So `Authorization` and
  `Cookie` are hidden only under those names, in a plain table.
- [ ] **Keep the hook cheap**, or hand the record to an `AsyncSink`. The hook runs on every response. An error raised by
  the hook is discarded, so test it.

## Listening and limits

### The address and the connections

- [ ] **The server listens where you mean it to.** `host` is an option of `server` with no configuration key. It
  defaults to `127.0.0.1`, this machine only.
  - In a container, set `server = { host = "0.0.0.0" }` (or `"::"`). Otherwise a published port answers nothing.
  - The host must be a numeric address. A name is refused, because it would bind every address it resolves to.
- [ ] **Bound the number of connections.** `max_connections` is an option of `server` with no configuration key. It has
  no default limit. Set one below the descriptor limit of the process (`ulimit -n`), and leave room for the database and
  outgoing connections. The other connections wait in the backlog.

### Time and size

- [ ] **Bound the time of an action.** The server has no timeout on the action. Wrap slow work in
  [`reactor.deadline`](../reference/glossary.md#concurrency), in the action or in a filter. Then a stuck dependency does
  not hold a connection forever.
  - Catch the `DeadlineExceededError` and answer 503 or 504 yourself.
  - Uncaught, it gives a generic 500 and a log record with no traceback.
- [ ] **Check the content and time limits.** Request content is limited to 1 MiB (`max_content`, a 413 beyond it). The
  content of a request must arrive within 300 seconds of its head (`request_timeout`, a 408 beyond it).
  - They apply to the whole server.
  - Raise them only if a route such as an upload needs it, and accept that every route gets the higher bound.
  - Every bound and its default is in [Set limits, timeouts and TLS on the HTTP
    server](http-limits-timeouts-and-tls.md).
- [ ] **Lower the nesting depth if your documents are shallow.** `limits.max_depth` bounds the nesting accepted by
  `hecate.json` and `hecate.schema` together (`HECATE_LIMITS__MAX_DEPTH`). Its default, 1000, is also its ceiling. A
  lower value makes a hostile, deeply nested document cheaper to refuse.
- [ ] **With TLS, bound the handshakes.** `max_handshakes` (default 64), `handshake_timeout` (default 10 seconds) and
  `max_handshake_bytes` (default 65536) limit what a silent or slow client can hold before its first request. See the
  TLS section of the limits guide.

## Workers and shutdown

### The workers

- [ ] **Choose the number of workers.** `server.workers` defaults to `1`: one process serves by itself
  (`HECATE_SERVER__WORKERS`). Above 1, the primary starts that many workers and spreads the connections with
  `server.strategy`. See [Multi-process serving](../explanation/multi-process-serving.md).
  - `auto` is `reuseport` where the platform and luv support it (Linux only), and `round_robin` otherwise.
  - Today it is `round_robin`, until a luv version supports `reuseport` (OQ-43).
  - `auto` falls back without a warning. A strategy you name that is not supported falls back with a warning.

### The signals

- [ ] **Signals reach the process.** Run the application as the first process of the container, or behind an init that
  forwards signals.
  - `SIGTERM` and `SIGINT` start a graceful shutdown. A second one stops at once.
  - With several workers, `SIGHUP` replaces them one at a time with workers running the new code. With one process it
    is ignored.
  - Windows delivers no `SIGTERM`. There, only Ctrl+C stops gracefully.
- [ ] **Keep signal handling on.** With `signals = false` the application does not watch signals. An ordinary process
  then ends on `SIGTERM` without draining. The first process of a Linux container ignores it, so nothing happens until
  the platform kills it at its timeout.

### The grace period

- [ ] **`server.grace_timeout` is shorter than the stop timeout of the platform.** It defaults to 30 seconds
  (`HECATE_SERVER__GRACE_TIMEOUT`). On `SIGTERM` or `SIGINT`, the requests in flight get that long to finish. Then they
  are cancelled.
  - `docker stop` waits 10 seconds before it kills the process. Kubernetes waits 30 seconds by default.
  - With the defaults of both, the platform kills the process before hecate is done.
  - Set the key a few seconds below the timeout of the platform, or raise the timeout of the platform.

## Next steps

- [Configure an application](configure-an-application.md): the layers, environment variables and secret files in detail.
- [Log structured records](log-structured-records.md): sinks, secrets and volume limits.
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md): every bound and its default.
