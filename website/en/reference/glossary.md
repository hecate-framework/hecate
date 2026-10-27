---
description: The vocabulary of hecate, taken from the academic literature, and the terms it replaces.
hecate: "0.x"
lua: "5.5"
order: 1
---

<!-- Public version of docs/glossary.md, adapted for the website (the name is never
     capitalised, links point to the repository). Keep it in step with the source. -->

# Glossary

hecate names things after the academic literature rather than after the idioms of other
languages ([ADR 0004](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0004-academic-vocabulary.md)). This glossary is **mandatory**
for public APIs, documentation and internal code.

## Rules

1. Prefer the term established in the literature over a term popularised by a language
   or framework (`future`, not `promise`; `fork`/`join`, not `spawn`/`all`).
2. **Standards win.** When an RFC or a specification we implement defines a term, use
   it: HTTP semantics (RFC 9110), problem details (RFC 9457), JSON Pointer (RFC 6901),
   URI templates (RFC 6570), JSON Schema 2020-12, OpenAPI 3.1, SQL.
3. When a theoretical term collides with a widely known practical meaning (relational
   algebra *selection* versus SQL `SELECT`), use the theoretical term and document the
   correspondence prominently (see "Relational algebra and SQL" below).
4. Identifiers are English, `snake_case` for functions, methods, fields and modules,
   `PascalCase` for classes, interfaces and traits.

## Concurrency

| Term | Meaning | Reference | Instead of |
|---|---|---|---|
| coroutine | Lua's native, asymmetric, stackful coroutine; the unit of execution | de Moura & Ierusalimschy, *Revisiting Coroutines* (2009) | fiber, green thread |
| reactor | Event demultiplexer dispatching I/O readiness/completion to handlers | Schmidt, *Reactor* pattern (1995) | event loop (acceptable in prose) |
| future | Placeholder for a value produced by a concurrent computation | Baker & Hewitt (1977); Friedman & Wise (1976) | promise, task |
| fork | Start a concurrent computation, returning a future | Conway (1963) | spawn, go, launch |
| spawn | Start an operating-system process (`reactor.spawn`); never a coroutine, which is a `fork` | POSIX `posix_spawn`; ADR 0023 | spawn for a coroutine |
| join | Wait for one or several futures | Conway (1963) | await all, gather, Promise.all |
| select | Wait for the first of several alternatives to become ready | Hoare, CSP (1978); Dijkstra, guarded commands (1975) | race, any |
| deadline | Absolute bound on the completion of a computation | — | timeout (a timeout is a relative duration; both may be accepted as arguments) |
| stream | Ordered sequence of bytes read, written and closed in order, over a file, a connection or another stream | Ritchie, *A Stream Input-Output System* (1984) | socket (for transports that are not sockets), channel (a channel carries values between coroutines) |
| back-pressure | A producer suspends while its consumer is slower, instead of buffering without bound | *Reactive Streams* specification (2015) | throttling, rate limiting |
| half-close | Ending one direction of a connection while the other stays usable (`shutdown`) | RFC 9293, section 3.6 | — |
| primary | The process that starts, supervises and, for some strategies, feeds the workers | Buschmann et al., *Pattern-Oriented Software Architecture* vol. 1 (1996), Master-Slave pattern | master, parent (for the operating-system relation, "parent process" is accepted) |
| worker | A process with its own reactor that serves requests; workers share nothing | Buschmann et al. (1996), Master-Slave pattern | slave, child process (for the operating-system relation) |
| message pipe | A framed connection between two processes that carries string messages and, optionally, a stream handle (`reactor.ipc`). Not to be confused with `PipeStream`, a local stream socket (Unix-domain socket, named pipe on Windows) | POSIX `pipe(2)`; ADR 0023 | channel (reserved for communication between coroutines) |
| peer | The remote end of a connection (`peer_address`) or of a message pipe (`Peer`) | RFC 9293 | remote (in "remote address"), client (when the role is unknown) |
| listening strategy | How the workers obtain connections: `reuseport` or `round_robin` ([ADR 0023](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0023-multi-process-serving.md)) | — | cluster mode |
| computation | A running unit of the scheduler: a coroutine started by `fork` or `detach`, or the main coroutine; what a scope owns and a future stands for | `concurrency.md` | task |
| suspension point (suspend) | A call at which the running coroutine yields to the reactor: every I/O operation and every waiting primitive of `hecate.reactor` (`join`, `select`, `sleep`, `scope`, `deadline`, channel and lock operations; `fork`, `detach`, `with_ambient` and `ambient` only require a managed coroutine). A suspended call does not block the reactor | `concurrency.md` | blocking, async |
| cancellation | Cooperative request to stop a computation | — | abort, kill |
| scope | Structured-concurrency region owning forked computations | Sústrik (2016); Smith, *nursery* (2018) | task group, nursery |
| ambient context | The immutable key-value bindings visible to a running computation and inherited, as they are at the moment of the call, by the computations it forks or detaches (`reactor.with_ambient`, `reactor.ambient`). An exception to explicit passing, for cross-cutting values | [ADR 0025](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0025-ambient-context.md); Swift task-local values; Java `ScopedValue` | thread-local, context variable, MDC |
| ambient binding | One key bound to one value while a call to `with_ambient` runs; it shadows an outer binding of the same key and disappears when the call returns or raises | ADR 0025 | — |
| ambient key | The identity of a binding: any non-nil value, a module-private table by convention, so that two packages cannot collide | ADR 0025 | — |
| logger context | The fields a `Logger` adds to every record (`context` option, `with_context`); it wins over the ambient context | `logging.md` | MDC |
| bound log fields | The fields bound by `log.bind` in the ambient context, which the default `context_provider` of a logger reads | `logging.md`; ADR 0025 | — |
| request context | The values bound in the ambient context around the serving of one request: the request id (`kernel`, with `log.bind`), possibly the principal (`security`) and a deadline budget; planned, not implemented | ADR 0025 | — |
| channel | Typed communication between coroutines | Hoare, CSP (1978) | queue (when used for communication) |
| semaphore | Counting synchronisation primitive | Dijkstra (1965) | limiter |
| mutex | Mutual exclusion lock | Dijkstra (1965) | lock (acceptable in prose) |
| monitor | Mutex with condition variables | Hoare (1974); Brinch Hansen (1973) | — |
| condition | Condition variable attached to a monitor | Hoare (1974) | event, signal |

## Object model and architecture

| Term | Meaning | Reference | Instead of |
|---|---|---|---|
| class | Template for objects with shared behaviour | — | — |
| trait | Reusable set of methods composed into a class with explicit conflict resolution | Schärli, Ducasse, Nierstrasz, Black (2003) | mixin (unless linearised mixins are meant), concern |
| interface | Set of required method signatures, checked for conformance | — | protocol (acceptable), contract (reserved for API contracts) |
| finalisation | Step that resolves trait composition and interface conformance, then flattens members into the class table | Schärli et al. (2003) | build, seal, compile |
| conformance | A class provides every method an interface requires | — | compliance |
| superclass | Class from which a class inherits (single inheritance) | — | parent class, base class |
| enumeration | Closed named set of values | — | enum |
| cause chain | Errors linked by `cause`, rendered by `__tostring` | — | — |
| inversion of control | The framework calls user code | Fowler (2004) | — |
| container | Object that resolves and constructs dependencies | Fowler (2004) | service locator (an anti-pattern, not a synonym) |
| service | An object registered in the container and resolved by it | Fowler (2004) | bean, provider |
| action | The controller method or function that a route invokes; what filters wrap. "Handler" is reserved for I/O completion handlers of the reactor | `http-and-routing.md` | handler |
| controller, route module, feature module | The two route declaration styles (a class of actions, or `hecate.routes(name)`) and the kernel's grouping of them into a feature module ([ADR 0006](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0006-declarative-routes-as-runtime-data.md)) | ADR 0006; `http-and-routing.md` | router group, blueprint, plugin; "module" alone, which is ambiguous with a Lua module |
| chain of responsibility | Ordered handlers around an action | Gamma et al. (1994) | middleware stack |
| filter | One element of the chain around an action | — | middleware |
| composition root | Single place where the object graph is assembled | Seemann (2011) | bootstrap file |
| entity | A class whose instances have an identity and are persisted by a data mapper | Evans (2003) | model, record |
| value object | Immutable object compared by value | Evans (2003) | DTO (when immutability is meant) |
| representation | The transferable form of a resource state | Fielding (2000); RFC 9110 | DTO, view model |

## Data

| Term | Meaning | Reference | Instead of |
|---|---|---|---|
| relation | Set of tuples over a heading of attributes | Codd (1970) | table (in the ORM API; "table" stays correct for SQL DDL) |
| tuple | Element of a relation | Codd (1970) | row, record |
| attribute | Named, typed component of a heading | Codd (1970) | column, field (in mapping metadata) |
| predicate | Boolean condition over tuples | Codd (1970) | where clause |
| projection (π) | Restriction to a subset of attributes | Codd (1970) | select columns |
| selection / restriction (σ) | Restriction to tuples satisfying a predicate | Codd (1970) | where / filter |
| join (⋈) | Combination of relations on a predicate | Codd (1970) | — |
| data mapper | Moves data between objects and a database, keeping them independent | Fowler, *PoEAA* (2002) | — |
| unit of work | Tracks changes during a business transaction and commits them atomically | Fowler, *PoEAA* (2002) | session, entity manager |
| identity map | Ensures each tuple is loaded once per unit of work | Fowler, *PoEAA* (2002) | cache |
| repository | Collection-like access to aggregates | Evans (2003); Fowler (2002) | DAO |
| database schema | The relations, constraints and indexes of a database (SQL DDL); not a `hecate.schema` type declaration | ISO/IEC 9075 | schema (alone, in data access) |
| migration | Versioned, reversible transformation of the database schema | — | — |
| connection pool | Bounded set of reusable connections | — | — |

### Relational algebra and SQL

| Relational algebra (hecate API) | SQL |
|---|---|
| `projection` | `SELECT a, b` |
| `selection` (also `restriction`) | `WHERE ...` |
| `join` | `JOIN ... ON ...` |
| `rename` (ρ) | `AS` |
| `union`, `intersection`, `difference` | `UNION`, `INTERSECT`, `EXCEPT` |

This table appears at the top of the `query` and `orm` reference pages.

## Types and validation

| Term | Meaning | Reference | Instead of |
|---|---|---|---|
| refinement type | A base type restricted by predicates (`integer` with `minimum = 1`) | Freeman & Pfenning (1991) | constrained type, validator |
| sum type / tagged union | Value that is exactly one of several variants | — | discriminated union (acceptable, OpenAPI term) |
| product type | Record of named components | — | — |
| coercion | Conversion of a textual input to a typed value | — | casting, parsing (when coercion is meant) |
| schema | Declaration of a type usable for validation, coercion and contract emission | JSON Schema 2020-12 | model, DTO |

Schema keywords follow JSON Schema 2020-12 vocabulary in `snake_case`: `minimum`,
`maximum`, `exclusive_minimum`, `multiple_of`, `min_length`, `max_length`, `pattern`,
`format`, `min_items`, `max_items`, `unique_items`, `enum`, `const`.

## HTTP

Terms from RFC 9110 are used as defined: *resource*, *representation*, *method*,
*status code*, *field* (header field), *content* (message body), *media type*.
Errors are *problem details* (RFC 9457; `hecate.problem.*` is the namespace). Path parameters follow URI Template syntax
(RFC 6570, level 1 subset).

## Logging

Severities follow RFC 5424: `emergency`, `alert`, `critical`, `error`, `warning`,
`notice`, `informational`, `debug`.
A *severity* is the urgency of a record; a logger records the severities at least as urgent as its own
`severity` option (never "level" or "threshold").
