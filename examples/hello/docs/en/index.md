---
description: What the hello example is, and what its documentation covers.
hecate: "0.x"
lua: "5.5"
order: 0
---

# hello

`hello` is a small JSON API built on hecate. It is the reference application of Phase 2: three routes, two
declaration styles, validated input, problem details and graceful shutdown.

This site is its documentation, written by hand and built with `hecate.doc`. It also shows what a project can
change in the look of the generated site: the palette in light and dark, the fonts, the radii and the logo.

> [!NOTE]
> The theme of this site is one CSS file and two images of the `public/` directory. The pages, the search and the
> navigation are the ones of every hecate documentation site.

## What it does

| Route | What it does |
|---|---|
| `GET /hello/{name}` | Greets a name: `{ "message": "Hello, Ada!" }`. |
| `POST /greetings` | Records a greeting in a language and answers `201`. |
| `GET /health` | Answers `{ "status": "ok" }`: the liveness probe. |

## Where to go next

- [Endpoints](guide/endpoints.md): each route, its input and its answers.
- [Errors](guide/errors.md): the `422` problem details and how to read them.
- [Request flow](guide/request-flow.md): what happens between the socket and the action.
- [Running it](guide/running.md): start the server, with workers, and stop it.
