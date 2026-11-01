---
description: How hecate.http models messages, runs a connection from accept to close, bounds every resource, and why its limits have the defaults they have.
hecate: "0.x"
lua: "5.5"
order: 4
---

# The HTTP model

This page explains how `hecate.http` represents messages, how a connection lives, and why the
limits and defaults are what they are. For recipes, see
[Serve HTTP](../how-to/serve-http.md).

`hecate.http` is a protocol layer built on [`hecate.net`](transport-model.md). It speaks
HTTP/1.1 ([RFC 9112](https://www.rfc-editor.org/rfc/rfc9112)) and follows the semantics of
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110). It has no routing, no HTTP/2 and no
WebSocket. Higher layers add routing and filters on top.

## The message model

A message is plain data with a few methods. The vocabulary is that of RFC 9110: *method*,
*target*, *status code*, *field*, *content* and *media type*.

- A `Request` has a `method`, a `target` (and its `path` and `query`), `fields` and content.
- A `Response` has a `status`, a `reason`, `fields` and content.
- `Fields` are case-insensitive, may hold several values for one name, and keep their order. They
  refuse CR, LF and NUL in a value and names that are not tokens. A smuggled line break never
  becomes a second field.
- `MediaType` parses and formats `Content-Type` values. `Status` knows reason phrases and which
  statuses never carry content.
- `Cookie` parses the `Cookie` field and `SetCookie` formats `Set-Cookie`, as RFC 6265 asks. A
  `Set-Cookie` field is never combined into one line.

The same classes serve the server and the client. An action returns a `Response`. The client
returns one too, with its content still on the wire.

### Content is a stream

The content of a message can be large, so it is a [stream](../reference/glossary.md#concurrency)
read on demand. A server request and a client response give a `ContentStream`: `read()` returns
one chunk at a time. `read_content(limit?)` collects the whole content within a bound.

The content of a message you build is more convenient. It is nil, a string, a table (JSON) or a
function that writes. The function form is what makes a response a stream: the framing (chunked
coding, or the declared length) is chosen from what you give. The `Content-Length`,
`Transfer-Encoding` and `Connection` fields are the protocol's own. The server and the client set
them and replace yours, so an action cannot corrupt the framing of a connection.

## The life of a connection

The server turns each layer of the work into a computation of a
[scope](../reference/glossary.md#concurrency):

1. `serve` runs an accept loop in a scope. Each accepted connection is a computation of that
   scope, so a slow client delays nobody.
2. With TLS, the handshake runs in the connection's own computation, never in the accept loop.
3. The connection reads from the stream in chunks of at most 16 KiB and feeds an incremental
   parser (llhttp, chosen in ADR 0019). It gets events: a [head](../reference/glossary.md#http), data, the end of a
   message.
4. Each request gets its own scope and one coroutine that runs the action. Cancelling the scope
   cancels the action and what it forked.
5. The server writes the response, drains the content the action left unread, and turns to the
   next request. Keep-alive (a [persistent connection](../reference/glossary.md#http)) is the default for HTTP/1.1.
6. The connection ends on `Connection: close`, an error, a timeout or a shutdown.

A connection serves its requests one at a time. When a client [pipelines](../reference/glossary.md#http) several requests, the
responses come in request order, as RFC 9112 requires. Concurrency comes from connections, not
from requests inside one.

The server reads the next bytes only after it has answered every request already parsed. This is
[back-pressure](../reference/glossary.md#concurrency): a client that pipelines faster than the
action works waits in the kernel buffers, not in the memory of the server.

### Errors never leak

An error becomes [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem details with a fixed
text chosen by the class of the failure. An action failure, a network failure and a parse failure
each have their own. The text of the real error, an address or an error number never reaches the
client. The application gets it through `on_error`. This is a security rule: an error message is
data about your server.

### Graceful shutdown

`shutdown(grace_timeout)` stops accepting, closes the connections that wait for a request and lets each
request in flight finish, with `Connection: close`. Only when the [grace period](../reference/glossary.md#http) expires are the remaining
requests cancelled. Nothing is cut in the middle of an answer unless it is late.

## The client's connection pool

A client keeps idle connections per [origin](../reference/glossary.md#http), because opening one costs a round trip, and a TLS
handshake costs more. It follows a few rules that make reuse safe:

- An idle connection expires after 30 seconds, before the server's 75, so the client is the one
  that closes.
- A connection with unread content, or with bytes left after a response, is never returned to the
  pool. A cancelled or failed request drops its connection, because its state is unknown.
- When a reused connection turns out to be dead before any byte of the response arrived, an
  idempotent request is retried once. A POST is never repeated: the server may have processed it.

## Why these limits

Every limit exists because an unbounded resource is an attack. A server that accepts a head of any
size, or waits forever for a byte, can be held by one client with a slow connection.

The server bounds each stage on its own, because the attacks differ:

| Stage | Bound | Defends against |
|---|---|---|
| The head | `head_timeout` as a whole-head deadline, and the parser limits | a client that sends one byte per interval (slowloris) |
| The wait between requests | `idle_timeout` | idle connections that hold descriptors |
| The content | `max_content`, `content_timeout`, `request_timeout` | a huge body, and a body that trickles |
| The response | `write_timeout` | a reader that never reads |
| The unread content | `drain_timeout` | a client that keeps a connection busy after the answer |
| The handshake | `handshake_timeout`, `max_handshakes`, `max_handshake_bytes` | a client that stalls the TLS handshake |

Two choices deserve a word.

`head_timeout` is a deadline on the whole head. `content_timeout` is a timeout between two reads.
A head is small, so a time budget for all of it is fair, and it is the defence against a client
that sends a byte at a time. Content may be large and slow legitimately, so only a stall cuts it.
`request_timeout` caps the total time, so a client that sends one byte per read still ends.

`max_connections` has no limit by default. A good number depends on the descriptor limit of the
process, which the deployment sets, and on whether a proxy caps connections upstream. Rather than
guess, the server stays bounded by the descriptor limit, `idle_timeout` and `head_timeout`, and
the guide says to set it.

When the accept loop meets descriptor exhaustion (`EMFILE`, `ENFILE`) or any other accept
failure, connections in service keep being served. The loop backs off from 50 ms to 1 s,
resumes by itself and reports the burst once to `logger` and `on_error`.

### Why these defaults

The values follow what common servers (nginx, Apache, Node, Go) choose:

- `max_content` is 1 MiB. An action that needs more asks for it, so no endpoint accepts
  uploads by accident.
- `head_timeout` is 60 seconds and `content_timeout` is 60 seconds, as common servers choose.
- `idle_timeout` is 75 seconds, the value of nginx. A proxy in front of Hecate should use a
  shorter one.
- `backlog` is 128, and the port is 8080.
- The parser limits are 8 KiB for a target and a field, 100 fields and 64 KiB for a head.
- The default host is `127.0.0.1`. Exposing the server is an explicit act.

A default is a statement about the typical case. The values are safe, not tuned. Measure your own
workload before you raise one.

## Strictness

The parser accepts HTTP/1.0 and HTTP/1.1 and nothing else. It refuses what RFC 9112 calls
dangerous when two readers could disagree on where a message ends: a `Content-Length` together
with `Transfer-Encoding`, several `Content-Length` values, a request line without a version.
These are the bases of request smuggling. Where llhttp is stricter than the RFC, Hecate keeps the
stricter behaviour. Forms follow the same principle: a malformed percent sequence is refused
instead of being guessed at.

The `Host` field must be a single valid host and port. An absolute-form target is accepted only
when its authority equals `Host`.

## What the server and the client do not do

- No per-request timeout for actions. An action that never returns holds its connection.
- A client that disconnects while its action runs is not detected until the next write.
- No limit on the number of requests per connection.
- `Transfer-Encoding: gzip, chunked` is read as chunked and not decompressed.
- The client has no proxy support, compression or cookie jar, and no hook to filter addresses.
- No HTTP/2.

## See also

- [Serve HTTP](../how-to/serve-http.md)
- [Set limits, timeouts and TLS on the HTTP server](../how-to/http-limits-timeouts-and-tls.md)
- [The transport model](transport-model.md)
- [TLS trust and security defaults](tls-trust-and-security.md)
