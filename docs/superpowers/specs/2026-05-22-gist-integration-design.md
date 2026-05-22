# Gist Integration — Design

**Date:** 2026-05-22
**Project:** `/home/yuhigawa/ws/personal/blogging`
**Status:** draft — awaiting trivium validation and user review
**Branch:** `feat/gist-integration`
**Predecessor:** [`2026-05-21-blog-engine-core-design.md`](./2026-05-21-blog-engine-core-design.md)

## Problem

The blog engine currently reads posts from `src/assets/posts/<group>/<leaf>.md`. To publish, you must commit a file, push, and let CI rebuild the container. That is fine for one author on one machine — it is fine for nobody else, and even for one author it makes "fix a typo" an engineering ceremony.

The original sketch always treated the local-MD source as a stepping stone toward GitHub Gists, because:

- a gist is a single edit-and-save unit, no `git push` required;
- the GitHub web UI / mobile app *is* the editor — no toolchain at all;
- ownership and identity ride for free on the GitHub account;
- the raw CDN (`gist.githubusercontent.com`) is already a CDN with no quota.

What is missing is the wiring: a discovery rule (which gists are posts? which files inside a gist?), a fetch path (what calls cost what?), and a failure mode (the rest of the page must not die when GitHub returns 503).

## Goals

1. **Posts live in GitHub Gists.** Editing a gist on github.com is the publish action. No rebuild, no redeploy.
2. **Convention by filename.** A file inside any of the user's public gists is a post iff its name matches `blog:<group>:<leaf>.md`. Other files (the user's normal gists, dotfiles, snippets) are silently ignored.
3. **Live fetch on every request.** No cache layer. The page always shows what the gists say *now*. (Cost is bounded — see Section 3.)
4. **Public gists only, anonymous fetch.** No tokens, no OAuth, no per-user state in v1.
5. **Engine survives GitHub being down.** API failure renders the layout with an empty menu and a small banner; status code stays 200.
6. **No regressions to the existing template-swap contract.** `<template id="template-<group>-<leaf>">` and `#dynamic-content` keep working. `menu_render`, `md`, `layout`, `static_serve`, `file_io` all stay byte-for-byte the same.

## Non-Goals (deferred)

- Authenticated gist fetch (private gists, raised rate limit).
- Multi-user blogs — exactly one configured username for v1.
- Caching, ETags, conditional `If-None-Match` requests.
- Webhooks or push-based updates.
- Filesystem fallback. The old `src/assets/posts/` source is being deleted entirely, not kept as a backup. Local-MD and gist-MD are not run side by side.
- Per-post URLs, syntax highlighting, image/table markdown — same deferrals as engine-core.
- Caching the GitHub TLS handshake / connection pooling across requests beyond what `gleam_httpc`/`hackney` provides out of the box.

## Architecture

```
┌──────────────────────────────────────────────────┐
│  request                                         │
└─────────┬────────────────────────────────────────┘
          │
   ┌──────▼───────┐    /static/*  ┌──────────────┐
   │   router     ├──────────────▶│ static serve │
   └──────┬───────┘                └──────────────┘
          │   (default)
   ┌──────▼───────────────────────┐
   │  gist.fetch_all(user)        │   ─┐
   │  → Result(List(Post), Err)   │    │  network: 1 list call
   └──────┬───────────────────────┘    │  + N raw fetches
          │                            │
    ┌─────┴──────┐                     │
    │  Ok        │  Error              │
    │            │                     │
    ▼            ▼                     │
┌────────┐  ┌────────────┐             │
│ build  │  │ banner +   │             │
│ menu + │  │ empty menu │             │
│ tpls   │  │ empty tpls │             │
└───┬────┘  └─────┬──────┘             │
    │             │                    │
    └──────┬──────┘                    │
           │                           │
    ┌──────▼───────────────────────┐   │
    │  layout.render(menu, tpls,   │◀──┘
    │  template, banner?)          │
    └──────────────────────────────┘
```

### Modules

| Module | Status | Responsibility |
|---|---|---|
| `blogging` | **modified** | router, boot-time template validation, per-request `gist.fetch_all → menu_render.build → layout.render`. No more boot-time scan. |
| `gist` | **new** | `pub fn fetch_all(user: String) -> Result(List(Post), GistError)`. One `GET https://api.github.com/users/<user>/gists` (paginated if needed) + one raw fetch per matching file. Returns `List(Post)` shaped exactly like `scanner.Post` used to be (group, leaf, body). |
| `menu_render` | unchanged | already takes `List(Post)`. The shape of `Post` is identical — only the module that produces it changes. |
| `md` | unchanged |  |
| `layout` | **minor change** | accepts an optional banner HTML string and a second token `<!-- {{banner}} -->`. When banner is absent, the token is replaced with the empty string. |
| `static_serve`, `file_io` | unchanged | static assets and template file load still come from disk. |
| `scanner` | **deleted** | filesystem post discovery is gone with v1 gist. |

`Post` lives in `gist.gleam` as the canonical type — one module, no indirection. `menu_render` imports `gist.Post`.

### Data type

```gleam
pub type Post {
  Post(group: String, leaf: String, body: String)
}

pub type GistError {
  NetworkError(reason: String)       // hackney / DNS / TLS
  HttpError(status: Int)              // any non-2xx including 403/429 (rate-limit)
  ParseError(reason: String)          // JSON shape unexpected
}
```

A single `HttpError(403)` (rate-limited) is not distinguished from generic `HttpError` — the UX is identical (banner + empty menu). Distinguishing it adds complexity for no behavior change.

## 1. Architecture (approved)

See the diagram above and the module table. The username is read from the **`BLOG_GIST_USER` environment variable** at boot time. An env var, not a TOML field, because `gleam.toml` is build-time metadata — there is no first-class runtime reader, and writing a one-off parser to read one value is silly.

If `BLOG_GIST_USER` is unset or empty, boot fails fast — same fail-fast discipline as engine-core's template-validation step. `docker-compose.yml` sets it: `BLOG_GIST_USER=Yuhigawa` for the default deploy.

## 2. Discovery & parsing rules (approved)

**Filename pattern** applied to every file in every gist returned by `GET /users/<user>/gists`:

```
^blog:([^:]+):([^:]+)\.md$
```

Group 1 is the menu group, group 2 is the leaf. **Neither may contain `:`.** This keeps the parser dead simple: `string.starts_with("blog:")`, strip prefix, `string.split(":")` → expect exactly 2 parts, ensure the second `string.ends_with(".md")`, drop the suffix. No regex engine required (Gleam stdlib has none). The function lives in `gist` as a private `parse_filename(name) -> Result(#(String, String), Nil)`.

Test the function explicitly with positive and negative cases (see Section 4).

**Slug normalization** is the same `slugify` already in `menu_render`:

- lowercase
- whitespace → `-`
- drop chars outside `[a-z0-9_-]`

Slugify applies to both `group` and `leaf` independently. `blog:Estudos:HTML Intro.md` → group `estudos`, leaf `html-intro`, template id `template-estudos-html-intro`. The unslugified `group` and `leaf` strings remain the displayed labels (preserves capitalization and spaces in the sidebar).

**Sort:** by `(slugify(group), slugify(leaf))` ascending — deterministic, matches the engine-core ordering.

**Collision rule:** if two files across different gists produce the same `(slug_group, slug_leaf)`, keep the first one encountered in API order and log a warning to stderr. Don't fail the request — a duplicate is a content mistake, not a server bug.

**Malformed names** (`blog::foo.md`, `blog:estudos:.md`, `blog:estudos:foo` no `.md`): regex misses → silently skipped. Strict over tolerant.

**Empty body:** valid. Renders an empty `<template>` element.

## 3. Per-request flow, networking & error handling

### Boot

1. Read `BLOG_GIST_USER` env var. Unset or empty → crash with a clear message ("set BLOG_GIST_USER=<github-username>").
2. Read template from disk (existing).
3. Validate `<!-- {{menu}} -->`, `<!-- {{templates}} -->`, and `<!-- {{banner}} -->` are present exactly once (existing + new banner token).
4. `elli.become(...)` — no network at boot, no scan.

### Per request to `/`

1. `gist.fetch_all(user)`.
2. On `Ok(posts)` → `menu_render.build(posts) → layout.render(template, menu, tpls, banner="")`.
3. On `Error(_)` → `layout.render(template, "", "", banner=<error banner>)`. Status code: **200**. Reason: the page still works (static layout, links), the menu is just empty.

### Network shape

| Call | Endpoint | Quota |
|---|---|---|
| List gists | `GET https://api.github.com/users/<user>/gists?per_page=100` | counts against the **anonymous 60/hr per-server-IP** GitHub API quota |
| Fetch body (× N matching files) | `GET https://gist.githubusercontent.com/<user>/<gist_id>/raw/<filename>` | **no quota** — CDN |

The 60/hr quota is **per server IP, not per visitor**. One Googlebot, one UptimeRobot, and one RSS poller already share that budget with real users. Expected steady-state failure mode under any meaningful crawler load: the banner shows up regularly, not just when GitHub is down. This is acceptable for v1 (the page still works, just empty-menu) and the answer when it actually hurts is caching — explicitly deferred. Documented so the operator knows what they're signing up for.

Pagination: `per_page=100` ceiling. If the user accumulates more than 100 gists, only the first page is read. Documented as a v1 limit. The Link header is ignored for now.

### Concurrency

The N raw fetches inside one request run **sequentially**. Easier to reason about, easier to test, and the typical N is small (<20). If a single user starts seeing >50 blog files, switch to a `Task.async_stream`-equivalent (Erlang `:rpc.pmap`-style) — out of scope for v1.

### Timeouts

- **Per-call timeout** — both list and raw fetches: 5 s total (TCP connect + headers + body, whichever expires first; whatever `gleam_httpc` exposes — wired uniformly).
- **Whole-request timeout (handler-level cap):** 15 s. The handler wraps `gist.fetch_all` in an Erlang `try`/timer such that if total elapsed time exceeds 15 s, the in-flight fetches are abandoned and the response falls back to the banner. This bounds the worst case at 15 s instead of `5 + N×5 = 55 s`.
- Any timeout → `NetworkError("timeout")` → banner.

### Observability

Every `GistError` reaches the handler is logged to stderr with the variant and the user being fetched (e.g., `[gist] HttpError(403) for user=Yuhigawa`). Without this, the operator (= the author) cannot distinguish "GitHub is down" from "we've been rate-limited all day". Collision warnings are logged with the same prefix. No structured metrics in v1.

### The banner

The error case substitutes this string into `<!-- {{banner}} -->`:

```html
<div class="error-banner" role="status">Couldn't reach GitHub right now — the menu will come back when GitHub does.</div>
```

The `<!-- {{banner}} -->` token lives **inside the sidebar**, below the menu group list — that way when the menu is empty (error case) the user still sees *why*. CSS for `.error-banner` lives in `src/assets/styles.css`: unobtrusive small text, muted color, no JS. On the `Ok` path the substitution is the empty string, so the markup is invisible.

## 4. Testing strategy

| Layer | Test type | What it covers |
|---|---|---|
| filename matcher | unit (`gleeunit`) | `parse_filename` returns `Ok(#(group, leaf))` for `blog:a:b.md`; returns `Error(Nil)` for `README.md`, `blog::x.md`, `blog:a:.md`, `notes.md`, `blog:a:b:c.md` (3+ colons is rejected by the "exactly 2 parts" rule), `blog:a:b.txt` (wrong suffix) |
| collision rule | unit | two posts → first wins, second dropped, warning emitted (stub the logger) |
| body fetch URL | unit | given gist id + filename, builds correct raw URL (regression test for URL encoding) |
| JSON parse | unit, fixture | feed a canned gist API JSON blob, get back expected `List(Post)` |
| HTTP layer | unit, **stubbed** | `gist.fetch_all` takes an `HttpClient` capability (record of two functions) so tests can inject canned 200/403/timeouts without hitting the network. Production code passes the live client. |
| Banner render | unit (`layout`) | `render(..., banner=string)` substitutes into `<!-- {{banner}} -->`; empty banner = empty substitution |
| Engine `Error` path | integration | inject an `HttpClient` that always errors; assert page contains the banner, no menu items, status 200 |
| Engine `Ok` path | integration | inject an `HttpClient` that returns a 2-gist fixture; assert menu HTML and rendered post bodies |
| End-to-end live | **gated** | one test that hits the real `https://api.github.com/users/Yuhigawa/gists`, runs only when `BLOG_LIVE_TEST=1` is set. CI does not set it. |

The `HttpClient` capability looks like:

```gleam
pub type HttpClient {
  HttpClient(
    list_gists: fn(String) -> Result(String, GistError),
    fetch_raw: fn(String) -> Result(String, GistError),
  )
}

pub fn fetch_all(client: HttpClient, user: String) -> Result(List(Post), GistError)
```

`blogging.gleam` constructs the production client once at boot (`gist.live_client()`); tests construct fake clients inline.

### Snapshot tests

The two existing snapshot files (`menu.html`, `index.html`) regenerate against the same `Post` shape — the fixture switches from "files on disk under `test/fixtures/posts/`" to "in-memory `[Post("estudos", "html", "..."), Post("estudos", "css", "...")]` defined directly in the test module". Existing assertions stand. Old `test/fixtures/posts/` directory is deleted along with `scanner_test.gleam`.

## Dependencies

New deps in `gleam.toml`:

- `gleam_httpc` (for HTTPS requests; uses `hackney` under the hood).
- `gleam_json` (parses the gist list JSON via `gleam/dynamic` decoders).

Both are first-party gleam-lang packages, stable, no transitive surprises.

The Erlang `hackney` HTTP client comes in transitively. It uses pooled connections — connection reuse across requests is automatic and free. **Caveat:** the `gleam_httpc` API may be synchronous-only; if so, the N raw fetches block the request process sequentially as documented in Section 3. Confirm during step 5.

## Files touched

```
src/blogging.gleam        modified   per-request fetch + render, banner wire-up
src/gist.gleam            NEW         fetch_all, HttpClient capability, parsing
src/layout.gleam          modified   banner token in validate + render
src/assets/styles.css     modified   .error-banner styles
src/assets/index.html     modified   add <!-- {{banner}} --> token
gleam.toml                modified   [blog] section + new deps

src/scanner.gleam         DELETE
test/scanner_test.gleam   DELETE
test/fixtures/posts/      DELETE
src/assets/posts/         DELETE

test/gist_test.gleam      NEW         all unit + integration tests above
test/fixtures/gist_list.json   NEW    canned API response
test/fixtures/raw/*.md    NEW         canned post bodies
```

`src/file_io.gleam` stays — `static_serve` and the template loader both still use it.

## Success criteria

The branch is done when, on `feat/gist-integration`:

1. `gleam test` runs and is green; total test count is at least 70 (current) minus the 5 scanner tests plus the new gist tests (~10 new = ~75 total).
2. `gleam format --check src test` passes.
3. `docker compose up blogging` boots, `curl localhost:3000/` returns a 200 HTML page whose sidebar reflects the live state of `Yuhigawa`'s public gists.
4. Pointing `BLOG_GIST_USER` at a non-existent user causes the page to still load with the banner inside the layout — no 500, no hang past the 5 s list-call timeout.
5. Editing a gist file on github.com and reloading shows the new content within one CDN-cache TTL (typically <1 minute for `gist.githubusercontent.com`).
6. The directory `src/assets/posts/` does not exist on the branch HEAD; nothing in the code references `scanner`.

## Plan / phasing

Single-branch, sequential. No per-task PRs. Each step lands as one commit on `feat/gist-integration`.

1. **Setup:** add `gleam_httpc`, `gleam_json` to `gleam.toml`; introduce `gist.gleam` containing only the `Post` and `GistError` types + an empty `HttpClient` record stub; migrate `menu_render` to `import gist` instead of `import scanner`. **Scanner stays in place**, so existing tests stay green.
2. **Banner token:** `layout` accepts a third `banner` parameter; `validate` requires `<!-- {{banner}} -->` exactly once; `index.html` gains the token inside the sidebar (below the menu group list). Pure-substitution test + layout unit tests updated. No network.
3. **Filename matcher:** private `parse_filename` in `gist`, unit tests covering all positive and negative cases in Section 4.
4. **`HttpClient` capability + `fetch_all` using a fake client:** the full assembly logic (list response → filter → fetch each → assemble `List(Post)` → sort → dedupe with warning log). Integration tests with a fake client cover Ok, partial-failure (one raw fetch errors, the rest succeed → those succeed and the failure is logged), and total-failure paths. No live HTTP yet.
5. **Live HTTP client:** `gist.live_client()` wired through `gleam_httpc` + `gleam_json` (uniform 5 s per-call timeout). Gated live test (`BLOG_LIVE_TEST=1`) asserts at least one `Post` comes back for `Yuhigawa`.
6. **Wire into `blogging.gleam`:** read `BLOG_GIST_USER` at boot; handler does per-request fetch + render with the 15 s whole-handler timeout cap; `Error` path logs to stderr and renders the banner. Scanner still exists at this point — its boot-time call is just no longer made.
7. **Delete scanner:** remove `src/scanner.gleam`, `test/scanner_test.gleam`, `test/fixtures/posts/`, `src/assets/posts/`. Verify no production code references `scanner` (`grep -r 'scanner' src/`). Update README. Tests green.

Step 6 is the riskiest single commit but is now strictly additive — scanner is dead code at that point, deletion is its own step. If 6 doesn't boot, revert is a one-commit affair without touching deletions.

## Hardening Log

Append lessons here as the implementation proceeds (same convention as `2026-05-21-blog-engine-core-design.md`). Each entry: step number, issue, fix, takeaway.

- **Step 1** — Plan claimed pre-task baseline was 70 tests; actual baseline was 69. Same count before and after Task 1. Takeaway: trust `gleam test` output, not plan-doc counts. (Cosmetic only.)
- **Step 1** — Plan's File Map mentioned a "transitive `gleam_dynamic`" added by `gleam_httpc`/`gleam_json`; in practice `manifest.toml` did not show it. Task 4 may need an explicit `gleam add gleam_dynamic` when decoder code lands.
- **Step 2** — When extending `layout.render` with a new token, never delete the substitution-order safety comment. Reviewer caught the deletion and asked for it back, extended to cover the new token. Takeaway: invariants documented near the code that depends on them survive churn; rules in only-spec-text rot.
