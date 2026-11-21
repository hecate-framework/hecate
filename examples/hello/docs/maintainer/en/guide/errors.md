---
description: The 422 problem details of hello and how to read each violation.
hecate: "0.x"
lua: "5.5"
order: 3
---

# Errors

Input that does not satisfy a schema is answered with `422` and problem details (RFC 9457). Each violation names
where it is and which rule it breaks.

```sh
curl -s -X POST localhost:8080/greetings \
  -H 'Content-Type: application/json' -d '{"name":""}'
```

| Member | Meaning |
|---|---|
| `pointer` | Where the violation is, relative to the source: `/name`. |
| `source` | Which part of the request: `content`, `path`, `query` or `header`. |
| `code` | The stable code of the violated rule. |

> [!WARNING]
> A violation never carries the rejected value or an error message: `errors.expose_details` defaults to `false`,
> because a rejected value can be a secret.

> [!TIP]
> Match on `code`, never on the text of a message: codes are stable, messages are not.
