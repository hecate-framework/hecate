---
description: A checklist of what to verify before you deploy a hecate application - environment, logging and redaction, secrets, error details, the access log, listening and limits, workers and shutdown.
hecate: "0.x"
lua: "5.5"
order: 15
---

# Before going to production

This guide is a checklist to go through before you deploy an application built with `hecate.kernel`. It is
written for hecate 0.x and Lua 5.5. Each item names the [configuration](../reference/glossary.md#configuration) key or
the option that controls it, and its default. Most defaults are already the safe choice: the list tells you which ones
are, and which ones you must set yourself.

A *key* is read from the configuration (files, environment variables, secret files) and applied by
`Application({ configuration = configuration })`; an explicit option of `Application` wins over its key. Some settings
are *options* only, with no key and no environment variable: the items say so. How layers, files and environment
variables combine is in [Configure an application](configure-an-application.md).

## The environment

- [ ] **The environment is `production`.** It is the `environment` option of `config.load`, else `HECATE_ENV`, else
  `production`. A process that is told nothing runs as production, so check that no deployment script, image or
  `.env` file sets `HECATE_ENV=development` or `HECATE_ENV=test`. To fail fast, check
  `configuration:environment() == "production"` in your entry point.
- [ ] **`config/production.lua` keeps the development settings out.** The development and test values
  (`errors.expose_details = true`, `requests.inputs = "lax"`) belong in `config/development.lua` and `config/test.lua`
  only, never in `config/default.lua`, which every environment reads.
- [ ] **Response validation is off, or on by choice.** The `validate_responses` option (no key) defaults to `true` in
  `development` and `test` and to `false` elsewhere. Turn it on in production only if you accept its cost on every
  response.

## Error details

- [ ] **`errors.expose_details` is `false`** (the default; `HECATE_ERRORS__EXPOSE_DETAILS`). When it is `true`, a 422
  entry carries the message of each violation, and a 500 carries the extension member `debug`: the error class, its
  message (for a plain Lua error, the source file and line) and, when the error object holds one, its traceback.
  Internal details reach the client.
- [ ] **Do not rely on the boot warning alone.** The application logs a `warning` with code
  `expose_details_in_production` at boot when the key is `true`, but only when a `configuration` is given and its
  environment is exactly `production`: an environment named `staging`, or `expose_details = true` passed as an option
  without a configuration, gives no warning. Fail the deployment if the record appears.
- [ ] **`requests.inputs` is `strict`** (the default; `HECATE_REQUESTS__INPUTS`). A request that carries an undeclared
  query parameter is then refused with a 422 naming each one (never its value), so a client learns about a misspelt
  parameter at once.

## Logging

- [ ] **Load the configuration with `kernel.load_configuration`**, not `config.load` directly. It passes
  `hecate.log.Secret` as the `wrap_secret` option, so every logging sink renders a secret key as `[redacted]`. A value
  wrapped by the fallback class of `hecate.config` still prints `[redacted]` through `tostring`, but a sink does not
  recognise it as a secret.
- [ ] **Let the configuration build the logger.** An explicit `logger` option of `Application` replaces the logger
  built from the `logging.*` keys, so none of them applies, `logging.redact` included: give such a logger its own
  `redact` list.
- [ ] **Choose the severity.** `logging.severity` defaults to `informational` (`HECATE_LOGGING__SEVERITY`). The names are
  the eight severities of RFC 5424, `emergency` to `debug`; there is no `info`. `debug` in production records far more
  than you need. `logging.severities` gives one logger a severity of its own, matched exactly against its name.
- [ ] **Choose the sinks.** `logging.sinks` defaults to `{ "console" }`, human-readable lines on the standard output. Use
  `json_lines` when a platform collects the logs: one JSON object per line, still on the standard output. `file` needs
  `logging.file.path`. Set `logging.async = true` to wrap each sink in an `AsyncSink` when a sink is slow, so that it
  does not hold up a request.
- [ ] **Know what the framework records.** At `informational` and above:
  - the listening address (`informational`), the workers started and reloaded (`notice`), the signals received
    (`notice`);
  - an unhandled error of an action (`error`, "unhandled error while serving a request"), with the method, the path
    **without** the query, the error class, its code, its message and the traceback;
  - an error the client caused (`warning`, "request refused"), with the same fields;
  - an action that fails in a way the kernel does not answer itself, such as an expired deadline (`error`, "http.Server:
    the action failed"), with the method, the path without the query and the error;
  - a failed TLS handshake (`warning`), with the address of the peer (behind a proxy, the proxy's address);
  - accept failures and connections a worker could not take (`warning`).

  Some answers are **not** logged: a problem with a status below 500 that an action returns or raises, and the requests
  the server refuses before any action runs (400, 408, 413, 414, 417, 431, 501). Only an access log sees them. The peer
  address is personal data in some jurisdictions: decide how long the records are kept.

## Secrets

- [ ] **Every secret key is listed in `secrets`.** Pass the dotted paths of the leaves to `kernel.load_configuration`,
  for example `secrets = { "database.password", "session.signing_key" }`. A listed key is wrapped after validation:
  `tostring` gives `[redacted]` and only `reveal()` gives the value. An unknown path is an `ArgumentError` at load, so a
  typo cannot leave a key unprotected. A key that is not listed is an ordinary string, printed in full by `describe()`,
  in error messages and in logs.
- [ ] **Secrets come from secret files**, or else from environment variables, never from a file of the repository. A
  secret key is read from the file named by `<NAME>_FILE` (for example `HECATE_DATABASE__PASSWORD_FILE`), or from
  `<secrets_directory>/<NAME>` when the `secrets_directory` option is set, as a Docker or Kubernetes secret is mounted.
  A secret file wins over the environment variable. Prefer files: child processes inherit the environment, and on Linux
  `/proc/<pid>/environ` shows it.
- [ ] **Call `reveal()` at the last moment**, where the value is used (the driver, the signing function), and never
  store the revealed value in a field of a record or an error.

## Redaction does not read free text

The logger redacts by **field name**, never by scanning text. This is the item that is easiest to get wrong.

- [ ] **`logging.redact` lists the names of your own sensitive fields** (`HECATE_LOGGING__REDACT`, comma separated). The
  names are added to `log.DEFAULT_REDACT`, the built-in list (`password`, `secret`, `token`, `api_key`,
  `authorization`, `cookie`, `session` and others), which is never replaced. Names are matched exactly,
  case-insensitively: `user_pin` does not match `pin`.
- [ ] **Names are matched in plain tables only.** A field nested in a plain table is redacted at any depth (up to 16
  levels): `{ headers = { authorization = token } }` is safe. An object with a metatable, such as `request.fields`, is
  not inspected, and the `json_lines` sink writes it as it is. Copy the fields you need into a plain table instead.
- [ ] **No secret is ever written into a message or an error message.** `logger:error("login failed for " .. password)`
  records the password, and so does `error("cannot connect with " .. dsn)`: the message of an unhandled error is a field
  of the record, and the client receives it too when `errors.expose_details` is `true`. Put values in named fields, or
  better leave them out: `logger:warning("login failed", { user = id })`.

## The access log

The framework writes no access log of its own. If you want one, pass an `on_response` hook in the `server` option of
`Application`. It receives, once per response, the method, the `target`, the status, the bytes sent, the duration,
`failed` (the response was not sent completely) and `refused` (the server answered before any action ran).

- [ ] **Strip the query from `target` before you record it.** `target` is the request target as received, query
  included, and a query string can carry a token (`?access_token=...`), an email address or a reset code. Record the part
  before `?`, as the records of the framework do, or record only the query parameters you know to be harmless.
- [ ] **Do not record request headers or content.** The redaction list matches field names, so `Authorization` and
  `Cookie` are hidden only under those names, in a plain table.
- [ ] **Keep the hook cheap**, or hand the record to an `AsyncSink`: it runs on every response. An error raised by the
  hook is discarded, so test it.

## Listening and limits

- [ ] **The server listens where you mean it to.** `host`, an option of `server` with no configuration key, defaults to
  `127.0.0.1`, this machine only. In a container, set `server = { host = "0.0.0.0" }` (or `"::"`), or a published port
  answers nothing. The host must be a numeric address: a name is refused, because it would bind every address it
  resolves to.
- [ ] **Bound the number of connections.** `max_connections`, an option of `server` with no configuration key, has no
  default limit: set one below the descriptor limit of the process (`ulimit -n`), leaving room for the database and
  outgoing connections.
- [ ] **Bound the time of an action.** The server has no timeout on the action. Wrap slow work in `reactor.deadline`, in
  the action or in a filter, so that a stuck dependency does not hold a connection forever. Catch the
  `DeadlineExceededError` and answer 503 or 504 yourself: uncaught, it gives a generic 500 and a log record with no
  traceback.
- [ ] **Check the content and time limits.** Request content is limited to 1 MiB (`max_content`, a 413 beyond it), and
  the content of a request must arrive within 300 seconds of its head (`request_timeout`, a 408 beyond it). They apply
  to the whole server: raise them only if a route such as an upload needs it, and accept that every route gets the
  higher bound. Every bound and its default is in [Set limits, timeouts and TLS on the HTTP
  server](http-limits-timeouts-and-tls.md).
- [ ] **Lower the nesting depth if your documents are shallow.** `limits.max_depth` (default 1000, the ceiling;
  `HECATE_LIMITS__MAX_DEPTH`) bounds the nesting accepted by `hecate.json` and `hecate.schema` together. A lower value
  makes a hostile, deeply nested document cheaper to refuse.
- [ ] **With TLS, bound the handshakes.** `max_handshakes`, `handshake_timeout` and `max_handshake_bytes` limit what a
  silent or slow client can hold before its first request; see the TLS section of the limits guide.

## Workers and shutdown

- [ ] **Choose the number of workers.** `server.workers` defaults to `1`, one process serving by itself
  (`HECATE_SERVER__WORKERS`). Above 1 the primary starts that many workers and spreads the connections with
  `server.strategy` (`auto` is `round_robin` until `reuseport` is supported). See [Multi-process
  serving](../explanation/multi-process-serving.md).
- [ ] **Signals reach the process.** Run the application as the first process of the container, or behind an init that
  forwards signals. `SIGTERM` and `SIGINT` start a graceful shutdown; a second one stops at once. With several workers,
  `SIGHUP` replaces them one at a time with workers running the new code; with one process it is ignored. Windows
  delivers no `SIGTERM`: there, only Ctrl+C stops gracefully.
- [ ] **Keep signal handling on.** With `signals = false` the application does not watch signals. An ordinary process
  then ends on `SIGTERM` without draining, and the first process of a Linux container ignores it, so nothing happens
  until the platform kills it at its timeout.
- [ ] **`server.grace_timeout` is shorter than the stop timeout of the platform.** It defaults to 30 seconds
  (`HECATE_SERVER__GRACE_TIMEOUT`): on `SIGTERM` or `SIGINT` the requests in flight get that long to finish, then they are
  cancelled. `docker stop` waits 10 seconds before it kills the process, Kubernetes 30 seconds by default: with the
  defaults of both, the platform kills the process before hecate is done. Set the key a few seconds below the platform's
  timeout, or raise the platform's.

## Next steps

- [Configure an application](configure-an-application.md): the layers, environment variables and secret files in detail.
- [Log structured records](log-structured-records.md): sinks, secrets and volume limits.
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md): every bound and its default.
