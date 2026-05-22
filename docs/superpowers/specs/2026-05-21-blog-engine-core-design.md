# Blog Engine Core — Design

**Date:** 2026-05-21
**Project:** `/home/yuhigawa/ws/personal/blogging`
**Status:** revision 2 — addresses trivium findings (idea 8, tech 7, qa 5 → revising to clear the gate)

## Problem

The current code is a toy:

- `blogging.gleam` hardcodes the list of posts (`["html.md", "css.md"]`).
- `index.html` hardcodes the sidebar menu structure.
- `render.parse_line` only knows `#`, `##`, and wraps everything else in `<p>` — empty lines included.
- `render.concatenate_templates` splices `<template>` blocks at the second-to-last line of `index.html`, which is fragile.
- The FFI swallows the real Erlang error reason and returns a generic `"file not found."` regardless of cause.
- `styles.css` was being `<link>`'d but did not exist; a route was added but it lives directly under `src/assets/` with no story for additional static files.
- No tests, no HTML escaping (XSS vector once posts contain `<script>`).

The design from the original sketch wants a menu driven by content nodes (eventually gists named `<group>/<leaf>`), markdown rendered into a layout, and a public URL. The local-MD phase needs to mirror that structure so swapping to gists later is a single substitution.

## Goals

1. Filesystem layout *is* the menu. `src/assets/posts/<group>/<leaf>.md` produces a sidebar entry under `<group>` with label `<leaf>` and content rendered from the file. Adding a file is the only step required to add a post.
2. A real (subset) Markdown parser with `gleeunit` tests per feature, **with HTML escaping** so post content can't inject script tags.
3. Generalized static-file serving from `src/assets/static/`.
4. Graceful failure modes — missing files do not crash the server, errors surface real typed reasons.
5. No regressions to the existing JS template-swap mechanism; the design from `index.html` (sidebar + `#dynamic-content` + `<template id="template-<group>-<leaf>">`) remains the contract between server and browser.

## Non-Goals (deferred)

- Gist/GitHub integration.
- ETS or any caching layer.
- Per-post URLs (`/posts/<id>`).
- Markdown images, tables, footnotes, GFM extensions beyond fenced code.
- Syntax highlighting.
- Profile data pulled from GitHub user API.
- Static-site export.
- Erlang release packaging (file paths assume cwd at this milestone; `priv_dir` lookup is a follow-up).

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
| `scanner` | walks `src/assets/posts/<group>/<leaf>.md`, returns `List(#(String, String, String))` sorted by `(group, leaf)` ascending |
| `md` | markdown → html for the supported subset; pure, well-tested; **escapes `<`, `>`, `&` in all text and code** |
| `menu_render` | takes scan result → builds sidebar `<nav>` HTML and `<template id="template-<group>-<leaf>">` blocks |
| `layout` | reads `index.html`, splices `{{menu}}` and `{{templates}}` placeholders; raises if a placeholder is missing or appears more than once |
| `static_serve` | maps `/static/<path>` to file under `src/assets/static/` with MIME inference |
| `markdown_server_ffi.erl` | `list_dir/1`, `read_text_file/1` returning typed Erlang tuples (`{ok, Bin} | {error, not_found} | {error, permission} | {error, {other, Bin}}`) |

`render.gleam` is split into `md.gleam`, `menu_render.gleam`, `layout.gleam`. Lower-cohesion code goes away.

### Templating contract

`index.html` becomes a template with two explicit placeholders:

- `<!-- {{menu}} -->` — inside `<nav class="menu">`, replaced with generated groups/items.
- `<!-- {{templates}} -->` — placed just before `</body>`, replaced with all `<template id="template-<group>-<leaf>">…</template>` blocks. The JS click handler is updated to look up by `template-<group>-<leaf>`.

`flatten_strings` is deleted. Splicing is by literal token replacement. Missing or duplicate placeholders raise at server start (fail-loud), not silently.

### Naming rules

- `<group>` and `<leaf>` slugs are the literal directory/filename minus `.md`. Displayed verbatim for the label. The `id=` attribute is derived by a deterministic transform applied in this order: (1) lowercase, (2) replace whitespace runs with single `-`, (3) drop any remaining character not in `[a-z0-9_-]`.
- If the transform yields an empty string or collides with a sibling's id, the file is skipped with a warning.
- The JS click handler reads `this.id` (the lowercased slug) and looks up `template-<group_id>-<leaf_id>`. `menu_render` tests assert that both the `<li id=…>` and the matching `<template id=template-…>` use the same transformed id.

### Scanner ordering and filtering

- Directories under `posts/` are groups; only direct children matter (no recursion beyond `group/leaf.md`).
- Files included: extension `.md` only. Hidden files (`.*`), `.gitkeep`, `README.md` and any non-`.md` files are ignored.
- Empty groups (no `.md` after filtering) are hidden from the menu.
- Sort order: groups ascending by name; leaves within a group ascending by name. Tests assert this deterministically so they pass on any FS.

## Markdown subset (parser scope)

In priority order. Each becomes its own sub-step with `gleeunit` tests.

1. **Block:** headings `#` … `######`, paragraphs (blank-line separated), `---` horizontal rule, blockquote `>`, fenced code ` ``` ` (no language detection yet), unordered list (`-`/`*`), ordered list (`1.`).
2. **Inline:** `**bold**`, `*italic*`, `` `code` ``, links `[text](url)`, backslash escape `\*`. Image syntax recognized but rendered as the link form for now (image support deferred).

**Escaping contract:** all text content (including inside `<code>` and `<pre>`) has `&`, `<`, `>` HTML-escaped before any tag emission. Attribute values from links (`href`) are escaped against quote-injection (`"`, `'`). This is a test-enforced invariant.

**Inline precedence:** code spans (`` ` ``) tokenize first and suppress emphasis inside. Emphasis runs (`*`, `**`) are resolved with a CommonMark-lite algorithm: longest-match first, no nesting of same delimiter. Documented intentional non-support: nested `**bold *italic***` may render as plain text; ambiguous unbalanced runs render literally. Tests pin these decisions.

Empty lines do not produce `<p></p>`. Unknown constructs render as escaped plain text (no crashes, no injection).

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

## Error handling

- FFI returns typed tuples (see Modules table). Gleam decodes via `gleam/dynamic` into a `FileError` enum (`NotFound`, `Permission`, `Other(String)`).
- Scanner failures on individual files log + skip rather than abort the page.
- Server returns 200 with the layout shell if no posts exist; `#dynamic-content` already handles the empty case.
- `/static/<unknown>` → 404 plain-text. Other unknown paths fall through to the index (single-page behavior preserved).
- Missing/duplicate placeholder in `index.html` → server fails to start with a clear log line (cheaper than mysterious blank pages).

## Testing

- `gleeunit` suite at `test/`. `gleam test` exit code is the merge gate.
- **Per-module unit tests:** `md` (per feature), `scanner` (fixture dir), `menu_render` (stubbed scan), `layout` (placeholder semantics), `static_serve` (MIME + 404), FFI (tuple decoding).
- **Cumulative MD suite:** a single `md_integration_test` with mixed-construct fixtures grows monotonically across sub-steps 5a–5f. After each sub-step, every prior fixture must still pass — this catches a later sub-step shadowing an earlier one.
- **End-to-end snapshot:** one test wires scanner → menu_render → layout against `test/fixtures/posts/` and asserts a golden rendered HTML string. Catches cross-module regressions cheaply.
- **Negative-path tests, all explicit:**
  - empty group is hidden
  - `.gitkeep` / `README.md` / hidden file inside a group is ignored
  - missing post file logged + skipped, page still renders
  - unknown `/static/foo` returns 404
  - missing `{{menu}}` placeholder raises at startup
  - `<script>` in post body is rendered escaped, not executed
  - duplicate `<group>-<leaf>` collision (cross-group) yields distinct template IDs
- **Snapshot update workflow:** snapshots live under `test/snapshots/<test_name>.html`; comparison is exact string match (no whitespace normalization — drift is signal, not noise). Failing snapshot prints diff + the command to regenerate (`GLEAM_UPDATE_SNAPSHOTS=1 gleam test`). Updates require a manual commit, never auto-applied in CI.
- **Known-failing test marker:** a test that is intentionally red until a later step lives in a `skip/<step>.gleam` file with a `// unskip-at: step 6a` comment. Skips count as zero in CI; removing the skip is part of the later step's "Done when". No `xfail` / red bars allowed in the suite.
- **CI gate:** `.github/workflows/test.yml` already exists; verify it runs `gleam test` on push to any branch. If not, fix as part of Step 1.
- **FFI negative decode:** the decoder for `{error, {other, Bin}}` has a test for malformed tuple shapes (wrong arity, wrong tag) — must return `Other("unrecognized: …")` rather than crash.

## Out of scope (re-stated for clarity)

Gists, cache, per-post URLs, MD images/tables, syntax highlighting, profile fetch, static export, release packaging. These come after this milestone lands and stabilizes.

## Build steps (each is one PR-sized unit; each gets a background reviewer)

Sequencing fixed: FFI typing lands first so the scanner is built against the final contract, and `static_serve` lands before the asset move so styling never breaks.

1. **FFI typing.** Update `markdown_server_ffi.erl` so `read_text_file/1` and the new `list_dir/1` pattern-match on `enoent` / `eacces` and return tagged tuples. Add `src/file_io.gleam` with the `FileError` enum and `gleam/dynamic` decoders. Tests: FFI tuple round-trip; decoder coverage for each error variant.
   - **Done when:** existing server still serves the index unchanged; new `file_io` API used internally by `render.file_to_string`; FFI tests pass.

2. **Static serving generalized.** New `src/static_serve.gleam` handling `/static/<path>` with MIME inference (`.css`, `.js`, `.svg`, `.png`, `.jpg`, `.woff2`). 404 for unknown. Tests: each MIME, traversal rejected (`..` in path), unknown extension yields `text/plain`, unknown path 404.
   - **Done when:** `/static/styles.css` serves the existing CSS; the old `/styles.css` route is kept as a temporary alias.

3. **Asset restructure.** Create `posts/estudos/{html,css}.md` and `posts/ensaios/.gitkeep`. Move `static/styles.css` into place. Update `<link>` to `/static/styles.css`. Remove the `/styles.css` alias from Step 2.
   - **Done when:** page renders identically to today with html/css posts visible (still served via the hardcoded list — scanner not wired yet).

4. **Scanner module.** New `src/scanner.gleam`. Walks `posts/<group>/<leaf>.md`, applies filtering + sorting rules from spec, returns `List(#(group, leaf, body))`. Tests with fixture tree under `test/fixtures/posts/` covering: normal case, empty group, ignored files, sort stability, missing-file skip.
   - **Done when:** scanner returns expected results for the fixture; existing server still uses hardcoded list (swap is Step 5).

5. **Menu + template generation, layout placeholders.** New `src/menu_render.gleam` and `src/layout.gleam`. Add `<!-- {{menu}} -->` and `<!-- {{templates}} -->` placeholders to `index.html`. Generate menu HTML + `<template id="template-<group>-<leaf>">` blocks from scan result. Delete `flatten_strings` and the hardcoded list. Update JS click handler to use `template-<group>-<leaf>`. Layout raises on missing/duplicate placeholder. Tests: stub-scan → expected menu HTML; placeholder presence; end-to-end snapshot test added.
   - **Done when:** page renders with menu generated from filesystem; end-to-end snapshot test passes; XSS escaping test for a `<script>` post passes (escaping isn't done yet — test should fail-then-be-pinned-as-known-gap-until-Step-6).

6. **Markdown parser, sub-stepped, each tested. Cumulative suite enforced after every sub-step.**
   - 6a. block headings (1–6) + paragraphs + blank-line handling + HTML escaping (`<`/`>`/`&`).
   - 6b. inline tokenizer — code spans first, then emphasis-run resolution (`**` / `*`), backslash escapes. Tests pin intentional non-support cases.
   - 6c. links `[text](url)` with attribute escaping.
   - 6d. lists (ul `-`/`*`, ol `1.`).
   - 6e. fenced code blocks (no language detection; content escaped).
   - 6f. blockquote `>` + horizontal rule `---`.
   - **Done when (each):** new feature tests pass AND every prior sub-step's tests still pass AND the XSS escaping test passes.

7. **README rewrite.** Document the engine model, the `posts/<group>/<leaf>.md` convention, slug rules, how to add a post, how to run tests, how to update snapshots.
   - **Done when:** README replaces the package-template boilerplate and reflects current state.

## Reviewer loop (hardening engineer)

After each step's edits land:

1. Dispatch a background subagent with: this design doc + the step number + step's "Done when" criteria + `git diff` output.
2. Subagent returns a structured finding list, one entry per issue:
   ```
   - step: <n>
     severity: blocker | major | minor
     file:line: <ref>
     issue: <one sentence>
     prevented-by-test: <test name, or "no">
   ```
3. Blocker + major findings are fixed before the next step starts. Minor findings are logged and may be batched.
4. After fixes, append a single line to **Hardening Log** below per *lesson learned* (not per finding) — format: `step N — <lesson> — prevented going forward by: <test or convention>`. No free-form prose. Entries that don't lead to a test or convention change are discarded.

## Hardening Log

(populated by the reviewer loop as steps complete)
