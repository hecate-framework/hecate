---
description: A checklist of what to verify before you deploy a hecate application - environment, logging and redaction, secrets, error details, the access log, listening and limits, workers and shutdown.
hecate: "0.x"
lua: "5.5"
order: 15
---

# Before going to production

This guide is a checklist to go through before you deploy an application built with `hecate.kernel`. It is written
for hecate 0.x and Lua 5.5.

Each item names the key or the option that controls it, and its default. Most defaults are already the safe choice.
The list tells you which ones are, and which ones you must set yourself.

A *key* is read from the [configuration](../reference/glossary.md#configuration), the validated key-value tree the
process is booted with. Keys come from files, environment variables and secret files, and
`Application({ configuration = configuration })` applies them. An explicit option of `Application` wins over its key.

Some settings are *options* only, with no key and no environment variable: the items say so. How layers, files and
environment variables combine is in [Configure an application](configure-an-application.md).

## The environment

The [environment](../reference/glossary.md#configuration) is the name of the deployment profile. It selects
`config/<environment>.lua`.

- [ ] **The environment is `production`.** It is the `environment` option of `config.load`, else `HECATE_ENV`, else
  `production`. A process that is told nothing runs as production.

  Check that no deployment script, image or `.env` file sets `HECATE_ENV=development` or `HECATE_ENV=test`. To fail
  fast, check `configuration:environment() == "production"` in your entry point.
- [ ] **`config/production.lua` keeps the development settings out.** The development and test values belong in
  `config/development.lua` and `config/test.lua` only:

  - `errors.expose_details = true`;
  - `requests.inputs = "lax"`;
  - a low `server.grace_timeout`.

  Never put them in `config/default.lua`, which every environment reads.
- [ ] **Response validation is off, or on by choice.** The `validate_responses` option (no key) defaults to `true` in
  `development` and `test`, and to `false` elsewhere. Turn it on in production only if you accept its cost on every
  response.

## Error details

- [ ] **`errors.expose_details` is `false`** (the default; `HECATE_ERRORS__EXPOSE_DETAILS`). When it is `true`:

  - a 422 entry carries the message of each [violation](../reference/glossary.md#types-and-validation);
  - a 500 carries the extension member `debug`.

  `debug` holds the error class, its message and, when the error object holds one, its traceback. For a plain Lua
  error, the message names the source file and line. `debug.message` holds the message of the error and of each of
  its causes, so the text of a wrapped driver error reaches the client too.
- [ ] **Do not rely on the boot warning alone.** The application logs a `warning` with code
  `expose_details_in_production` at boot when the key is `true`. It does so only when a `configuration` is given and
  its environment is exactly `production`.

  An environment named `staging` gives no warning. Neither does `expose_details = true` passed as an option without a
  configuration. Fail the deployment if the record appears.
- [ ] **`requests.inputs` is `strict`** (the default; `HECATE_REQUESTS__INPUTS`). A request that carries an undeclared
  query parameter is then refused with a 422. The answer names each such parameter, never its value, so a client
  learns about a misspelt parameter at once.

## Logging

- [ ] **Load the configuration with `kernel.load_configuration`**, not `config.load` directly. It passes
  `hecate.log.Secret` as the `wrap_secret` option, so every logging sink renders a secret key as `[redacted]`.

  `config.load` alone does the same only when `hecate.log` is already loaded. Otherwise it uses its own class. That
  class still prints `[redacted]` through `tostring`, but a sink does not recognise it as a secret.
- [ ] **Let the configuration build the logger.** An explicit `logger` option of `Application` replaces the logger
  built from the `logging.*` keys. None of them applies then, `logging.redact` included: give such a logger its own
  `redact` list.
- [ ] **Choose the severity.** A [severity](../reference/glossary.md#logging) is the urgency of a record.
  `logging.severity` defaults to `informational` (`HECATE_LOGGING__SEVERITY`).

  The names are the eight severities of RFC 5424, `emergency` to `debug`; there is no `info`. `debug` in production
  records far more than you need. `logging.severities` gives one logger a severity of its own, matched exactly against
  its name.
- [ ] **Choose the sinks.** `logging.sinks` defaults to `{ "console" }`: human-readable lines on the standard output.

  - Use `json_lines` when a platform collects the logs: one JSON object per line, still on the standard output.
  - `file` needs `logging.file.path`.
  - Set `logging.async = true` to wrap each sink in an `AsyncSink` when a sink is slow, so that it does not hold up a
    request.
- [ ] **Know what `logging.async` loses.** Each `AsyncSink` queues at most 1024 records. Past that, it drops records
  silently. The sink counts them, but the logger built from the configuration gives no access to that count.
- [ ] **Own the permissions and the retention of the log file.** The `file` sink creates its file with the permissions
  the umask of the process leaves, and it never rotates the file. Set the umask, the permissions of the directory and
  the retention yourself.

### What the framework records

- [ ] **Know what the framework records.** At `informational` and above, it records:

  - the listening address (`informational`), the workers started and reloaded (`notice`), and the signals received
    (`notice`);
  - an unhandled error of an action (`error`, "unhandled error while serving a request");
  - an error the client caused (`warning`, "request refused"), with the same fields as an unhandled error;
  - an action that fails in a way the kernel does not answer itself, such as an expired deadline (`error`,
    "http.Server: the action failed"), with the method, the path without the query, and the error;
  - a failed TLS handshake (`warning`), with the address of the [peer](../reference/glossary.md#concurrency), the
    remote end of the connection. Behind a proxy, that is the proxy's address;
  - accept failures, and connections a worker could not take (`warning`).

  The record of an unhandled error holds the method, the path **without** the query, the error class, its code, its
  message and the traceback.

  - While `errors.expose_details` is false, the `traceback` field names each cause of the error by its class and code
    only (`caused by: hecate.postgresql.QueryError (23505)`), never by its message.
  - With the key true (development and test), it carries the message of each cause too. A wrapped driver error then
    brings its text into the logs.
  - With the key true, an error that carries violations (a failed `check`) also logs the JSON Pointer of the first one
    in the `pointer` field. That pointer can hold a key the client sent; no message ever names it.

  Some answers are **not** logged:

  - an input the kernel refuses (422, 400 for content that is not JSON, 415), which is returned, not raised;
  - a problem with a status below 500 that an action returns or raises;
  - the requests the server refuses before any action runs (400, 408, 413, 414, 417, 431, 501).

  Only an access log sees them.

  The peer address is personal data in some jurisdictions: decide how long the records are kept.
- [ ] **Keep personal data out of paths.** The logged `path` drops the query, but not the path parameters. A route
  such as `/users/{email}` writes the email address into every record of a failed request.
- [ ] **Never log the argument of `on_error` whole.** The `on_error` option of `server` receives the error object
  itself, with its context and its causes. A connection string or a driver message can be in them. Record its class
  and its code instead.

## Secrets

- [ ] **Every secret key is listed in `secrets`.** Pass the dotted paths of the leaves to `kernel.load_configuration`,
  for example `secrets = { "database.password", "session.signing_key" }`.

  A listed key is wrapped after validation in a [secret object](../reference/glossary.md#configuration): `tostring`
  gives `[redacted]`, and only `reveal()` gives the value. An unknown path is an `ArgumentError` at load, so a typo
  cannot leave a key unprotected.

  A key that is not listed is an ordinary string. It is printed in full by `describe()`, in logs, and in any message
  the application builds with it. The validation errors of `config.load` never quote a value, listed or not.

  Once every secret key is listed, `configuration:describe()` is safe to log at boot.
- [ ] **Secrets come from secret files**, or else from environment variables, never from a file of the repository. A
  [secret file](../reference/glossary.md#configuration) holds the value of one secret key. A secret key is read from:

  - the file named by `<NAME>_FILE`, for example `HECATE_DATABASE__PASSWORD_FILE`;
  - or `<secrets_directory>/<NAME>`, when the `secrets_directory` option is set, as a Docker or Kubernetes secret is
    mounted.

  A secret file wins over the environment variable. Prefer files: child processes inherit the environment, and on
  Linux `/proc/<pid>/environ` shows it.
- [ ] **Call `reveal()` at the last moment**, where the value is used (the driver, the signing function). Never store
  the revealed value in a field of a record or an error.

## Redaction does not read free text

The logger redacts by **field name**, never by scanning text. This is the item that is easiest to get wrong.

- [ ] **`logging.redact` lists the names of your own sensitive fields** (`HECATE_LOGGING__REDACT`, comma separated).
  The names are added to `log.DEFAULT_REDACT`, the built-in list, which is never replaced. That list holds
  `password`, `secret`, `token`, `api_key`, `authorization`, `cookie`, `session` and others.

  Names are matched exactly, case-insensitively: `user_pin` does not match `pin`.
- [ ] **Names are matched in plain tables only.** A field nested in a plain table is redacted at any depth, up to 16
  levels: `{ headers = { authorization = token } }` is safe.

  An object with a metatable, such as `request.fields`, is not inspected, and the `json_lines` sink writes it as it
  is. Copy the fields you need into a plain table instead.
- [ ] **No secret is ever written into a message or an error message.**
  `logger:error("login failed for " .. password)` records the password. So does `error("cannot connect with " .. dsn)`: the message of an unhandled error
  is a field of the record, and the client receives it too when `errors.expose_details` is `true`.

  Put values in named fields, or better leave them out: `logger:warning("login failed", { user = id })`.

## The access log

The framework writes no access log of its own. If you want one, pass an `on_response` hook in the `server` option of
`Application`. It receives, once per response:

- the method and the `target`;
- the status;
- the bytes sent and the duration;
- `failed`: the response was not sent completely;
- `refused`: the server answered before any action ran.

The items below apply to that hook.

- [ ] **Strip the query from `target` before you record it.** `target` is the request target as received, query
  included. A query string can carry a token (`?access_token=...`), an email address or a reset code.

  Record the part before `?`, as the records of the framework do. Or record only the query parameters you know to be
  harmless.
- [ ] **Do not record request headers or content.** The redaction list matches field names, so `Authorization` and
  `Cookie` are hidden only under those names, in a plain table.
- [ ] **Keep the hook cheap**, or hand the record to an `AsyncSink`: it runs on every response. An error raised by the
  hook is discarded, so test it.

## Listening and limits

- [ ] **The server listens where you mean it to.** `host`, an option of `server` with no configuration key, defaults
  to `127.0.0.1`: this machine only.

  In a container, set `server = { host = "0.0.0.0" }` (or `"::"`), or a published port answers nothing. The host must
  be a numeric address. A name is refused, because it would bind every address it resolves to.
- [ ] **Bound the number of connections.** `max_connections`, an option of `server` with no configuration key, has no
  default limit. Set one below the descriptor limit of the process (`ulimit -n`), leaving room for the database and
  outgoing connections.
- [ ] **Bound the time of an action.** The server has no timeout on the action. Wrap slow work in
  `reactor.deadline`, in the action or in a filter, so that a stuck dependency does not hold a connection forever.

  Catch the `DeadlineExceededError` and answer 503 or 504 yourself. Uncaught, it gives a generic 500 and a log record
  with no traceback.
- [ ] **Check the content and time limits.** Two bounds apply to every request:

  - request content is limited to 1 MiB (`max_content`, a 413 beyond it);
  - the content of a request must arrive within 300 seconds of its [head](../reference/glossary.md#http), its start
    line and fields (`request_timeout`, a 408 beyond it).

  They apply to the whole server. Raise them only if a route such as an upload needs it, and accept that every route
  gets the higher bound. Every bound and its default is in
  [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md).
- [ ] **Lower the nesting depth if your documents are shallow.** `limits.max_depth` (default 1000, the ceiling;
  `HECATE_LIMITS__MAX_DEPTH`) bounds the nesting accepted by `hecate.json` and `hecate.schema` together. A lower value
  makes a hostile, deeply nested document cheaper to refuse.
- [ ] **With TLS, bound the handshakes.** `max_handshakes`, `handshake_timeout` and `max_handshake_bytes` limit what a
  silent or slow client can hold before its first request. See the TLS section of the limits guide.

## Workers and shutdown

- [ ] **Choose the number of workers.** `server.workers` defaults to `1`: one process serving by itself
  (`HECATE_SERVER__WORKERS`).

  Above 1, the [primary](../reference/glossary.md#concurrency), the process that starts and supervises the workers,
  starts that many [workers](../reference/glossary.md#concurrency). It spreads the connections with
  `server.strategy`, the [listening strategy](../reference/glossary.md#concurrency) (`auto` is `round_robin` until
  `reuseport` is supported). See [Multi-process serving](../explanation/multi-process-serving.md).
- [ ] **Signals reach the process.** Run the application as the first process of the container, or behind an init that
  forwards signals.

  - `SIGTERM` and `SIGINT` start a graceful shutdown; a second one stops at once.
  - With several workers, `SIGHUP` replaces them one at a time with workers running the new code. With one process, it
    is ignored.
  - Windows delivers no `SIGTERM`: there, only Ctrl+C stops gracefully.
- [ ] **Keep signal handling on.** With `signals = false`, the application does not watch signals. An ordinary process
  then ends on `SIGTERM` without draining. The first process of a Linux container ignores it, so nothing happens until
  the platform kills it at its timeout.
- [ ] **`server.grace_timeout` is shorter than the stop timeout of the platform.** It is the
  [grace period](../reference/glossary.md#http), and defaults to 30 seconds (`HECATE_SERVER__GRACE_TIMEOUT`). On
  `SIGTERM` or `SIGINT`, the requests in flight get that long to finish, then they are cancelled.

  `docker stop` waits 10 seconds before it kills the process, Kubernetes 30 seconds by default. With the defaults of
  both, the platform kills the process before hecate is done. Set the key a few seconds below the platform's timeout,
  or raise the platform's.

## Next steps

- [Configure an application](configure-an-application.md): the layers, environment variables and secret files in detail.
- [Log structured records](log-structured-records.md): sinks, secrets and volume limits.
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md): every bound and its default.
