# Blog Engine Core — Design

**Date:** 2026-05-21
**Project:** `/home/yuhigawa/ws/personal/blogging`
**Status:** approved (auto mode), pending trivium gate

## Problem

The current code is a toy:

- `blogging.gleam` hardcodes the list of posts (`["html.md", "css.md"]`).
- `index.html` hardcodes the sidebar menu structure.
- `render.parse_line` only knows `#`, `##`, and wraps everything else in `<p>` — empty lines included.
- `render.concatenate_templates` splices `<template>` blocks at the second-to-last line of `index.html`, which is fragile.
- The FFI swallows the real Erlang error reason and returns a generic `"file not found."` regardless of cause.
- `styles.css` was being `<link>`'d but did not exist; a route was added but it lives directly under `src/assets/` with no story for additional static files.
- No tests.

The design from the original sketch wants a menu driven by content nodes (eventually gists named `<group>/<leaf>`), markdown rendered into a layout, and a public URL. The local-MD phase needs to mirror that structure so swapping to gists later is a single substitution.

## Goals

1. Filesystem layout *is* the menu. `src/assets/posts/<group>/<leaf>.md` produces a sidebar entry under `<group>` with label `<leaf>` and content rendered from the file. Adding a file is the only step required to add a post.
2. A real (subset) Markdown parser with `gleeunit` tests per feature.
3. Generalized static-file serving from `src/assets/static/`.
4. Graceful failure modes — missing files do not crash the server, errors surface real reasons.
5. No regressions to the existing JS template-swap mechanism; the design from `index.html` (sidebar + `#dynamic-content` + `<template id="template-<leaf>">`) remains the contract between server and browser.

## Non-Goals (deferred)

- Gist/GitHub integration.
- ETS or any caching layer.
- Per-post URLs (`/posts/<id>`).
- Markdown images, tables, footnotes, GFM extensions beyond fenced code.
- Syntax highlighting.
- Profile data pulled from GitHub user API.
- Static-site export.

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
   ┌──────▼───────┐
   │  index.gleam │
   └──────┬───────┘
          │
   ┌──────▼───────────────────────┐
   │  scanner.scan_posts()        │
   │  → List(#(group, leaf, md))  │
   └──────┬───────────────────────┘
          │
   ┌──────▼───────────────────────┐    ┌────────────────┐
   │  menu_render.build(scan)     │    │  md.to_html    │
   │  → menu_html, templates[]    │◀───┤  (per leaf)    │
   └──────┬───────────────────────┘    └────────────────┘
          │
   ┌──────▼───────────────────────┐
   │  layout.render(menu, tpls)   │
   │  splices into index.html     │
   └──────────────────────────────┘
```

### Modules

| Module | Responsibility |
|---|---|
| `blogging` | elli setup + top-level routing only |
| `scanner` | walks `src/assets/posts/<group>/<leaf>.md`, returns `List(#(String, String, String))` |
| `md` | markdown → html for the supported subset; pure, well-tested |
| `menu_render` | takes scan result → builds sidebar `<nav>` HTML and `<template>` blocks |
| `layout` | reads `index.html`, splices `{{menu}}` and `{{templates}}` placeholders |
| `static_serve` | maps `/static/<path>` to file under `src/assets/static/` with MIME inference |
| `markdown_server_ffi.erl` | `list_dir/1`, `read_text_file/1` returning real `{error, Reason}` |

`render.gleam` is split into `md.gleam`, `menu_render.gleam`, `layout.gleam`. Lower-cohesion code goes away.

### Templating contract

`index.html` becomes a template with two explicit placeholders:

- `<!-- {{menu}} -->` — inside `<nav class="menu">`, replaced with generated groups/items.
- `<!-- {{templates}} -->` — placed just before `</body>`, replaced with all `<template id="template-<leaf>">…</template>` blocks.

`flatten_strings` (insert at length-1) is deleted. Splicing is by literal token replacement.

## Markdown subset (parser scope)

In priority order. Each becomes its own sub-step with `gleeunit` tests.

1. **Block:** headings `#` … `######`, paragraphs (blank-line separated), `---` horizontal rule, blockquote `>`, fenced code ` ``` ` (no language detection yet), unordered list (`-`/`*`), ordered list (`1.`).
2. **Inline:** `**bold**`, `*italic*`, `` `code` ``, links `[text](url)`. Image syntax recognized but rendered as the link form for now (image support deferred).

Empty lines do not produce `<p></p>`. Unknown constructs render as plain text (no crashes).

## Filesystem layout

```
src/assets/
  index.html              # template with placeholders
  static/
    styles.css
  posts/
    estudos/
      html.md
      css.md
    ensaios/
      .gitkeep            # group exists, no posts yet → group hidden in UI
```

Empty groups (no `.md` children) are hidden from the menu.

## Error handling

- FFI returns `{error, Reason}` where `Reason` is the original Erlang term coerced to a binary; Gleam side maps to a typed `FileError` enum (`NotFound`, `Permission`, `Other(String)`).
- Scanner failures on individual files log + skip rather than abort the page.
- Server still returns 200 with the layout shell if no posts exist; `#dynamic-content` already handles the empty case.
- `/static/<unknown>` returns 404 with a plain-text body. Other unknown paths fall through to the index (single-page behavior preserved).

## Testing

- `gleeunit` suite at `test/`.
- One test file per parser block + one per inline feature.
- Snapshot-style assertions: input markdown → expected HTML string.
- `scanner` tested via a temp fixture directory.
- `menu_render` tested with a stub scan result.

## Out of scope (re-stated for clarity)

Gists, cache, per-post URLs, MD images/tables, syntax highlighting, profile fetch, static export. These come after this milestone lands and stabilizes.

## Build steps (each is one PR-sized unit; each gets a background reviewer)

1. **Restructure assets.** Create `posts/<group>/<leaf>.md` layout; move `html.md` → `posts/estudos/html.md`, same for `css.md`. Move `styles.css` → `static/styles.css`. Update the `/styles.css` route to `/static/styles.css` (and the `<link>` in `index.html`).
2. **Scanner module.** New `src/scanner.gleam` + new FFI `list_dir`. Returns scan results. Unit-tested with a fixture directory under `test/fixtures/posts/`.
3. **Menu + template generation.** New `src/menu_render.gleam`. Replaces both the hardcoded `["html.md", "css.md"]` list in `blogging.gleam` and the hardcoded `<ul>` inside `index.html`. Adds `{{menu}}` and `{{templates}}` placeholders to `index.html`. Delete `flatten_strings`.
4. **Generalize static route.** New `src/static_serve.gleam` handling `/static/*` with MIME mapping (`.css`, `.js`, `.svg`, `.png`, `.jpg`, `.woff2`). 404 for unknown.
5. **Markdown parser, sub-stepped, each tested:**
   - 5a. block headings + paragraphs + blank-line handling.
   - 5b. inline emphasis (`**`, `*`, `` ` ``).
   - 5c. links `[text](url)`.
   - 5d. lists (ul + ol).
   - 5e. fenced code blocks.
   - 5f. blockquote + hr.
6. **FFI error pass-through.** `read_text_file` and `list_dir` return real reasons. Gleam side maps to typed errors.
7. **README rewrite.** Document the engine model, the `posts/<group>/<leaf>.md` convention, and how to add a post.

## Reviewer loop (hardening engineer)

After each step's edits land:

1. Dispatch a background subagent with: this design doc + the step number + `git diff` output.
2. Subagent verifies: design intent met, no adjacent regressions, tests present and meaningful, naming/structure consistent with prior steps.
3. Findings returned as a short list of issues + severities.
4. Issues fixed before the next step starts.
5. Lessons appended to this design doc under "Hardening Log" so the next step avoids the same trap.

## Hardening Log

(populated by the reviewer loop as steps complete)
