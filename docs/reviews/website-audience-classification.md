# Website pages by audience: proposed classification

Status: **classification approved by the owner on 2026-11-21, including the three doubts and the answers below; the move itself is the roadmap item `website`** (OQ-144, issue
[#223](https://github.com/hecate-framework/hecate/issues/223); owner direction of 2026-11-21).

The Hecate website becomes two documentation sites, each built from its own content tree:
`website/user/<locale>/...` and `website/maintainer/<locale>/...`, published as `/user/en/...` and
`/maintainer/en/...`, with `/` redirecting to the user site. The French mirror moves with its English page.

## The test

A page is **user documentation** if it is needed to build, run or operate an application on the public API of
Hecate, including the concepts that help a user do so and the public extension points. A page is **maintainer
documentation** if it is needed to change Hecate itself: its architecture, internals, decisions, CI and release,
benchmark method. A page that serves both goes in the tree of its main reader and is linked from the other site by an
absolute URL (a page is never duplicated).

## English pages

| Page | Title | Proposed | Why |
| --- | --- | --- | --- |
| `index.md` | hecate | user | landing page of the public site |
| `explanation/index.md` | Explanation | user | section index |
| `explanation/concurrency-model.md` | The concurrency model | user | a user writes concurrent code against it |
| `explanation/http-model.md` | The HTTP model | user | what a handler receives and returns |
| `explanation/object-model.md` | The object model: classes, traits, interfaces | user | public API of `core` |
| `explanation/schemas-and-contracts.md` | Schemas and contracts | user | contract-first is the user's workflow |
| `explanation/transport-model.md` | The transport model | user | streams, buffering and deadlines a user relies on |
| `explanation/multi-process-serving.md` | Multi-process serving | user | operating an application |
| `explanation/tls-trust-and-security.md` | TLS trust and security defaults | user | operating an application |
| `explanation/architecture-and-layers.md` | Architecture and layers | maintainer (approved) | explains the layering of packages, which only matters when changing Hecate; its section "The life of a request" moves to a new user page (next row) and this page links to it |
| `explanation/life-of-a-request.md` (new) | The life of a request | user (owner, 2026-11-21) | the section "The life of a request" of the architecture page (lines 63 to 87 today), split into its own page so that a page is never duplicated; the maintainer page links to it |
| `how-to/index.md` | How-to guides | user | section index |
| `how-to/before-going-to-production.md` | Before going to production | user | operating |
| `how-to/concurrency.md` | Concurrency: fork, join, select, deadlines, channels and shared state | user | public API |
| `how-to/configure-an-application.md` | Configure an application | user | public API |
| `how-to/connect-and-serve-over-tcp.md` | Connect and serve over TCP | user | public API |
| `how-to/deadlines-and-cancellation.md` | Deadlines and cancellation on streams | user | public API |
| `how-to/encode-and-decode-json.md` | Encode and decode JSON | user | public API |
| `how-to/filters.md` | Filters | user | public extension point |
| `how-to/handle-forms-and-multipart.md` | Handle forms and multipart | user | public API |
| `how-to/http-limits-timeouts-and-tls.md` | Set limits, timeouts and TLS on the HTTP server | user | operating |
| `how-to/log-structured-records.md` | Log structured records | user | public API |
| `how-to/map-domain-errors-to-problem-details.md` | Map domain errors to problem details | user | public API |
| `how-to/measure-performance.md` | Measure performance | maintainer (approved) | describes the benchmark harness of the repository; a user measuring their own application may want it |
| `how-to/multi-process-deployment.md` | Multi-process deployment, graceful shutdown and health checks | user | operating |
| `how-to/normalise-unicode-strings.md` | Normalise Unicode strings | user | public API (`hecate.unicode`) |
| `how-to/offload-cpu-bound-work.md` | Offload CPU-bound work to the thread pool | user | public API |
| `how-to/route-requests.md` | Route requests | user | public API |
| `how-to/run-processes-and-pass-connections.md` | Run child processes and pass connections between processes | user | public API |
| `how-to/serve-and-export-the-contract.md` | Serve and export the contract | user | public API |
| `how-to/serve-http.md` | Serve HTTP | user | public API |
| `how-to/stream-http-content.md` | Stream HTTP content | user | public API |
| `how-to/test-an-application.md` | Test an application | user | public API (`hecate.test`) |
| `how-to/tls-client-and-server.md` | TLS client and server | user | public API |
| `how-to/udp-pipes-and-dns.md` | UDP, Unix sockets, named pipes and DNS | user | public API |
| `how-to/use-the-container.md` | Use the container | user | public API |
| `how-to/use-the-http-client.md` | Use the HTTP client | user | public API |
| `how-to/validate-with-schemas.md` | Validate values with schemas | user | public API |
| `reference/index.md` | Reference | user | section index |
| `reference/error-codes.md` | Error codes | user | generated; codes reach API clients |
| `reference/glossary.md` | Glossary | user (approved) | vocabulary for both audiences; kept once in the user tree and linked from the maintainer site |
| `reference/project-documentation.md` | Project documentation | user | how to generate a project's documentation |
| `reference/schema-keywords-and-formats.md` | Schema keywords and formats | user | public API |
| `reference/theme-tokens.md` | Theme tokens | user | customising a project's documentation site |

## Generated reference pages

The code reference of every package (`reference/<package>/...`, about 300 generated pages) follows the rule of the code
reference of a project: public symbols go to the user tree, `*.internal` modules and private or package classes to the
maintainer tree (`reference_site.run` with `audience_locale_dirs`).

## The architecture specifications and the ADRs

Owner decision (2026-11-21): the maintainer site **publishes** `docs/architecture/` and the ADRs (`docs/adr/`). They stay
where they are in the repository, which remains their source of truth: the maintainer tree receives generated pages
(git-ignored, like the code reference), so a document is never copied by hand. The mechanism is settled when the
`website` roadmap item starts: a task that writes each file into the maintainer tree with the front matter a page needs
(title from the first heading, `description`), and rewrites the links between those documents and to the glossary, the
roadmap and the other files of `docs/`. `docs/roadmap.md`, `docs/open-questions.md` and `docs/reviews/` are not part of this
decision: they are not published until the owner says so.

## Decisions of the owner (2026-11-21)

1. The maintainer site publishes `docs/architecture/` and the ADRs, besides the generated internals and the pages classified
   as maintainer above.
2. `/` redirects to the user site.
3. `architecture-and-layers` is maintainer documentation; its section "The life of a request" becomes the user page
   `explanation/life-of-a-request.md`.
4. `measure-performance` is maintainer documentation; the glossary is user documentation, linked from the maintainer site.
