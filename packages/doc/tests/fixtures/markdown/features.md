# Every supported construct

Paragraph with *emphasis*, **strong text**, ***both***, ~~strikethrough~~, `inline code`, a
[link](https://example.test/a?b=1&c=2 "Title"), a [reference link][ref], an
![image](https://example.test/pic.png "Caption"), <https://example.test> and a hard  
break.

[ref]: https://example.test/ref

## Lists

- tight item
- another
  - nested item
  - second nested

1. first
2. second

3) other delimiter

- [x] done task
- [ ] open task

A loose list:

- loose item

- another loose item

## Code

```lua
---@param name string
global <const> print
print("hello", 42) -- comment
```

```sh
$ hecate new --name app
```

```json
{ "key": [1, true, null] }
```

    indented code

## Table

| Name | Type | Default |
|:-----|:----:|--------:|
| `a`  | text | 1       |
| `b`  | flag | 2       |

## Quote and containers

> A quote
> with two lines.

::: note
A note.
:::

::: tip A custom title
A tip.
:::

::: warning
A warning.
:::

::: danger
A danger.
:::

---

<!-- a comment is dropped -->

Raw <b>HTML</b> is shown as text, and [bad](javascript:alert(1)) links are not links.

Setext heading
--------------
