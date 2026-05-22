# Blog Engine Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** turn the toy Elli server into a real local-MD blog engine: typed FFI errors, generalized static serving, filesystem-as-menu, a tested Gleam markdown parser with HTML escaping. Defers gist integration.

**Architecture:** seven modules with single responsibilities — `blogging` (router), `file_io` (FFI wrapper + typed errors), `scanner` (walks `posts/<group>/<leaf>.md`), `md` (markdown → escaped HTML), `menu_render` (sidebar + `<template>` blocks from scan), `layout` (placeholder splice into `index.html`), `static_serve` (`/static/*` with MIME). Existing `render.gleam` is dissolved into these.

**Tech Stack:** Gleam 1.5.1, Erlang/OTP 26, Elli, gleeunit, `gleam_http`, `gleam/dynamic` for FFI decoding.

**Spec:** `docs/superpowers/specs/2026-05-21-blog-engine-core-design.md`

**Reviewer loop:** after each Task completes (a "Step" in the spec), dispatch a background subagent with the spec + that task's Done-when + the git diff. Blocker/major findings get fixed before the next Task. Lessons go to the spec's Hardening Log as one-line entries.

---

## File Map

**New:**
- `src/file_io.gleam` — `FileError` enum + `read_text/1` + `list_dir/1` wrappers
- `src/static_serve.gleam` — `/static/*` handler
- `src/scanner.gleam` — walks `posts/<group>/<leaf>.md`
- `src/md.gleam` — markdown → HTML (subset, escaping invariant)
- `src/menu_render.gleam` — scan result → menu HTML + `<template>` blocks
- `src/layout.gleam` — splice placeholders into `index.html`
- `src/assets/posts/estudos/{html,css}.md` — moved from `src/assets/{html,css}.md`
- `src/assets/posts/ensaios/.gitkeep` — empty group fixture
- `src/assets/static/styles.css` — moved from `src/assets/styles.css`
- `test/file_io_test.gleam`, `test/scanner_test.gleam`, `test/md_test.gleam`, `test/md_integration_test.gleam`, `test/menu_render_test.gleam`, `test/layout_test.gleam`, `test/static_serve_test.gleam`, `test/end_to_end_test.gleam`
- `test/fixtures/posts/...` — fixture tree
- `test/snapshots/...` — golden HTML
- `test/skip/xss_pending.gleam` — known-failing test, unskip at Task 6a

**Modified:**
- `src/blogging.gleam` — router only; uses every module above
- `src/markdown_server_ffi.erl` — tagged tuples for errors, adds `list_dir/1`
- `src/render.gleam` — **deleted** at Task 5 (functionality redistributed)
- `src/assets/index.html` — placeholders `{{menu}}` / `{{templates}}`; updated JS click handler
- `test/blogging_test.gleam` — keeps gleeunit `main()`, removes hello_world test
- `README.md` — engine docs

---

## Conventions used in every task

**TDD cadence:** write failing test → run to confirm RED → minimal impl → run to confirm GREEN → commit.

**Run commands (toolchain lives in Docker):**
- All tests: `docker compose run --rm --no-deps blogging gleam test`
- Format check: `docker compose run --rm --no-deps blogging gleam format --check src test`
- Format apply: `docker compose run --rm --no-deps blogging gleam format src test`
- Boot server: `docker compose up` (port 3000)
- Single test: gleeunit has no native filter; run the whole suite and grep the output for the test name.

**Commit format:** `feat: <what>` for new behavior, `refactor: <what>` for moves, `test: <what>` for test-only commits, `chore: <what>` for build/docs.

**After each Task:** dispatch reviewer subagent as described in the spec's reviewer-loop. Apply blocker/major findings before starting next Task. Append a one-line lesson to spec's Hardening Log only if it leads to a future-step convention or test.

---

## Task 1: FFI typing + `file_io` module

**Spec mapping:** Step 1 (FFI typing first so downstream consumes final contract).

**Files:**
- Modify: `src/markdown_server_ffi.erl`
- Create: `src/file_io.gleam`
- Create: `test/file_io_test.gleam`
- Modify: `src/render.gleam` (route `file_to_string` through `file_io`)

**Done when:** server still serves the index unchanged; `file_io` API used internally; FFI tests pass; CI workflow file unchanged (already runs `gleam test`).

- [ ] **Step 1: Write the failing FFI decoder tests**

`test/file_io_test.gleam`:

```gleam
import file_io
import gleeunit/should

pub fn read_text_existing_test() {
  // assumes src/assets/index.html exists (it does)
  let assert Ok(content) = file_io.read_text("src/assets/index.html")
  content
  |> string_contains("<!DOCTYPE")
  |> should.be_true
}

pub fn read_text_not_found_test() {
  file_io.read_text("does/not/exist.txt")
  |> should.equal(Error(file_io.NotFound))
}

pub fn list_dir_existing_test() {
  let assert Ok(entries) = file_io.list_dir("src/assets")
  // index.html is in there
  entries
  |> list_member("index.html")
  |> should.be_true
}

pub fn list_dir_not_found_test() {
  file_io.list_dir("does/not/exist")
  |> should.equal(Error(file_io.NotFound))
}

pub fn decoder_malformed_other_test() {
  // Simulated: FFI returns an unexpected tuple shape; decoder must produce Other(_) not crash.
  file_io.decode_error_for_test(dynamic_from(#("error", "weird_shape", 42)))
  |> should.equal(file_io.Other("unrecognized: see logs"))
}

import gleam/string
fn string_contains(s: String, sub: String) -> Bool { string.contains(s, sub) }

import gleam/list
fn list_member(xs: List(a), x: a) -> Bool { list.contains(xs, x) }

import gleam/dynamic.{type Dynamic}
@external(erlang, "erlang", "term_to_binary")
fn term_to_binary(t: a) -> BitArray
fn dynamic_from(t: a) -> Dynamic { dynamic.from(t) }
```

- [ ] **Step 2: Run to verify it fails**

Run: `gleam test`
Expected: compile error — `file_io` does not exist.

- [ ] **Step 3: Update Erlang FFI to return tagged tuples + add `list_dir`**

Replace `src/markdown_server_ffi.erl` with:

```erlang
-module(markdown_server_ffi).
-export([read_text_file/1, list_dir/1]).

to_bin_string(Data) ->
    unicode:characters_to_binary(Data).

read_text_file(Filename) ->
    case file:read_file(Filename) of
        {ok, Data}            -> {ok, to_bin_string(Data)};
        {error, enoent}       -> {error, not_found};
        {error, eacces}       -> {error, permission};
        {error, Reason}       -> {error, {other, to_bin_string(io_lib:format("~p", [Reason]))}}
    end.

list_dir(Path) ->
    case file:list_dir(Path) of
        {ok, Entries}         -> {ok, [to_bin_string(E) || E <- Entries]};
        {error, enoent}       -> {error, not_found};
        {error, eacces}       -> {error, permission};
        {error, Reason}       -> {error, {other, to_bin_string(io_lib:format("~p", [Reason]))}}
    end.
```

- [ ] **Step 4: Implement `src/file_io.gleam`**

```gleam
import gleam/dynamic.{type Dynamic}
import gleam/result

pub type FileError {
  NotFound
  Permission
  Other(String)
}

@external(erlang, "markdown_server_ffi", "read_text_file")
fn ffi_read(path: String) -> Result(String, Dynamic)

@external(erlang, "markdown_server_ffi", "list_dir")
fn ffi_list(path: String) -> Result(List(String), Dynamic)

pub fn read_text(path: String) -> Result(String, FileError) {
  ffi_read(path) |> result.map_error(decode_error)
}

pub fn list_dir(path: String) -> Result(List(String), FileError) {
  ffi_list(path) |> result.map_error(decode_error)
}

pub fn decode_error_for_test(d: Dynamic) -> FileError {
  decode_error(d)
}

fn decode_error(d: Dynamic) -> FileError {
  case dynamic.classify(d) {
    "Atom" ->
      case dynamic.string(d) {
        Ok("not_found") -> NotFound
        Ok("permission") -> Permission
        _ -> Other("unrecognized: see logs")
      }
    "Tuple of 2 elements" -> decode_other_tuple(d)
    _ -> Other("unrecognized: see logs")
  }
}

fn decode_other_tuple(d: Dynamic) -> FileError {
  case dynamic.tuple2(dynamic.string, dynamic.string)(d) {
    Ok(#("other", msg)) -> Other(msg)
    _ -> Other("unrecognized: see logs")
  }
}
```

- [ ] **Step 5: Route `render.file_to_string` through `file_io`**

`src/render.gleam` — replace the body of `file_to_string`:

```gleam
import file_io

pub fn file_to_string(file_path: String) -> String {
  let full_file_path = "src/assets/" <> file_path
  case file_io.read_text(full_file_path) {
    Ok(content) -> content
    Error(_) -> "<h1>Error reading file</h1>"
  }
}
```

(Keep the old `@external` declaration in `render.gleam` removed; only `file_io` talks to the FFI now. `convert_markdown_to_html` continues to call `read_text_file` — change that line to use `file_io.read_text` too, returning `"<h1>Error reading file</h1>"` on `Error`.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `gleam test`
Expected: all green; the four `file_io` tests pass; existing `hello_world_test` still passes.

- [ ] **Step 7: Verify the server still works**

Run: `./start_server.sh`, browse `http://localhost:3000`, confirm sidebar and content render as before.

- [ ] **Step 8: Commit**

```bash
git add src/markdown_server_ffi.erl src/file_io.gleam src/render.gleam test/file_io_test.gleam
git commit -m "feat: typed FFI errors via file_io module"
```

- [ ] **Step 9: Dispatch reviewer subagent** (background) with Task 1 done-when + diff.

---

## Task 2: `/static/*` handler with temporary `/styles.css` alias

**Spec mapping:** Step 2.

**Files:**
- Create: `src/static_serve.gleam`
- Create: `test/static_serve_test.gleam`
- Modify: `src/blogging.gleam`

**Done when:** `/static/styles.css` serves CSS with `text/css`; `/styles.css` alias still works (temporary, removed at Task 3); `/static/..%2F..%2Fetc%2Fpasswd` rejected; unknown extension → `text/plain`; missing file → 404.

- [ ] **Step 1: Write the failing tests**

`test/static_serve_test.gleam`:

```gleam
import gleam/bit_array
import gleam/option.{None, Some}
import gleeunit/should
import static_serve

pub fn mime_css_test() {
  static_serve.mime_for("foo.css") |> should.equal("text/css; charset=utf-8")
}

pub fn mime_unknown_test() {
  static_serve.mime_for("foo.bin") |> should.equal("text/plain; charset=utf-8")
}

pub fn resolve_normal_test() {
  static_serve.resolve("styles.css") |> should.equal(Some("src/assets/static/styles.css"))
}

pub fn resolve_traversal_rejected_test() {
  static_serve.resolve("../../etc/passwd") |> should.equal(None)
}

pub fn resolve_absolute_rejected_test() {
  static_serve.resolve("/etc/passwd") |> should.equal(None)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `gleam test`
Expected: compile error — `static_serve` not found.

- [ ] **Step 3: Implement `src/static_serve.gleam`**

```gleam
import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/response.{type Response}
import gleam/option.{type Option, None, Some}
import gleam/string
import file_io

pub fn serve(path: String) -> Response(BytesBuilder) {
  case resolve(path) {
    None -> not_found()
    Some(full) ->
      case file_io.read_text(full) {
        Ok(body) ->
          response.new(200)
          |> response.prepend_header("content-type", mime_for(path))
          |> response.set_body(bytes_builder.from_string(body))
        Error(_) -> not_found()
      }
  }
}

pub fn resolve(path: String) -> Option(String) {
  case string.starts_with(path, "/") || string.contains(path, "..") {
    True -> None
    False -> Some("src/assets/static/" <> path)
  }
}

pub fn mime_for(path: String) -> String {
  case extension(path) {
    "css"  -> "text/css; charset=utf-8"
    "js"   -> "text/javascript; charset=utf-8"
    "svg"  -> "image/svg+xml"
    "png"  -> "image/png"
    "jpg"  -> "image/jpeg"
    "jpeg" -> "image/jpeg"
    "woff2"-> "font/woff2"
    _      -> "text/plain; charset=utf-8"
  }
}

fn extension(path: String) -> String {
  case string.split(path, ".") {
    [] -> ""
    parts -> {
      let assert Ok(last) = list_last(parts)
      string.lowercase(last)
    }
  }
}

import gleam/list
fn list_last(xs: List(String)) -> Result(String, Nil) {
  case list.reverse(xs) {
    [h, ..] -> Ok(h)
    [] -> Error(Nil)
  }
}

fn not_found() -> Response(BytesBuilder) {
  response.new(404)
  |> response.prepend_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(bytes_builder.from_string("not found"))
}
```

- [ ] **Step 4: Wire router + temporary alias**

Modify `src/blogging.gleam` to route `/static/<rest>` and keep `/styles.css` as alias:

```gleam
import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/string
import render
import static_serve

pub fn server_handler(req: Request(t)) -> Response(BytesBuilder) {
  case req.path {
    "/styles.css" -> static_serve.serve("styles.css")
    _ -> case string.starts_with(req.path, "/static/") {
      True -> static_serve.serve(string.drop_left(req.path, 8))
      False -> serve_index()
    }
  }
}

fn serve_index() -> Response(BytesBuilder) {
  let html_content = render.file_to_string("index.html")
  let concatenated_content =
    render.concatenate_templates(html_content, ["html.md", "css.md"])
  let body = bytes_builder.from_string(concatenated_content)
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(body)
}

pub fn main() {
  elli.become(server_handler, on_port: 3000)
}
```

Note: at this Task `src/assets/static/styles.css` does not exist yet — Task 3 moves it. To keep the server functional through this Task, copy (don't move) the existing CSS:

```bash
mkdir -p src/assets/static && cp src/assets/styles.css src/assets/static/styles.css
```

- [ ] **Step 5: Run tests + boot server**

Run: `gleam test` → all green.
Run: `./start_server.sh`, browse `/`, `/styles.css`, `/static/styles.css`, `/static/missing.css`, `/static/..%2Fetc%2Fpasswd` — confirm 200/200/200/404/404.

- [ ] **Step 6: Commit**

```bash
git add src/static_serve.gleam src/blogging.gleam src/assets/static/styles.css test/static_serve_test.gleam
git commit -m "feat: /static/* handler with mime inference + traversal guard"
```

- [ ] **Step 7: Reviewer subagent** (background) with Task 2 done-when + diff.

---

## Task 3: Asset restructure (`posts/<group>/<leaf>.md`)

**Spec mapping:** Step 3.

**Files:**
- `git mv src/assets/html.md → src/assets/posts/estudos/html.md`
- `git mv src/assets/css.md → src/assets/posts/estudos/css.md`
- Create: `src/assets/posts/ensaios/.gitkeep`
- Delete: `src/assets/styles.css` (the copy in `src/assets/static/styles.css` remains)
- Modify: `src/assets/index.html` — `<link>` already points to `/static/styles.css`? Check; if not, update.
- Modify: `src/blogging.gleam` — update hardcoded list to new paths; remove `/styles.css` alias.
- Modify: `src/render.gleam` `convert_markdown_to_html` to take a relative path under `src/assets/` (existing behavior) — the list passed in changes.

**Done when:** page renders identically to today with html/css posts visible; `/styles.css` returns 404 (alias gone); `/static/styles.css` works.

- [ ] **Step 1: Move post files + add empty group**

```bash
mkdir -p src/assets/posts/estudos src/assets/posts/ensaios
git mv src/assets/html.md src/assets/posts/estudos/html.md
git mv src/assets/css.md  src/assets/posts/estudos/css.md
touch src/assets/posts/ensaios/.gitkeep
git add src/assets/posts/ensaios/.gitkeep
```

- [ ] **Step 2: Delete old top-level styles.css**

```bash
git rm src/assets/styles.css
```

- [ ] **Step 3: Confirm index.html link**

Verify `<link rel="stylesheet" href="styles.css">` — change to `<link rel="stylesheet" href="/static/styles.css">`.

- [ ] **Step 4: Update server router + template list**

`src/blogging.gleam` — remove `/styles.css` alias and update list:

```gleam
case req.path {
  _ -> case string.starts_with(req.path, "/static/") {
    True -> static_serve.serve(string.drop_left(req.path, 8))
    False -> serve_index()
  }
}
```

And in `serve_index`:

```gleam
render.concatenate_templates(html_content, [
  "posts/estudos/html.md",
  "posts/estudos/css.md",
])
```

- [ ] **Step 5: Verify by booting**

Run: `./start_server.sh`, browse `/`. Confirm: page renders, css applied, both posts click-loadable.
Check: `curl -i http://localhost:3000/styles.css | head -1` → `HTTP/1.1 404`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move posts under posts/<group>/<leaf>.md"
```

- [ ] **Step 7: Reviewer subagent** with Task 3 done-when + diff.

---

## Task 4: `scanner` module

**Spec mapping:** Step 4.

**Files:**
- Create: `src/scanner.gleam`
- Create: `test/scanner_test.gleam`
- Create: `test/fixtures/posts/estudos/{html,css}.md`
- Create: `test/fixtures/posts/ensaios/.gitkeep`
- Create: `test/fixtures/posts/skipme/README.md` (must be ignored)
- Create: `test/fixtures/posts/skipme/.hidden` (must be ignored)

**Done when:** scanner returns the expected sorted list for the fixture tree; ignored files (`.gitkeep`, hidden, non-`.md`) excluded; empty groups (no `.md` after filtering) absent from output.

- [ ] **Step 1: Create fixtures**

```bash
mkdir -p test/fixtures/posts/estudos test/fixtures/posts/ensaios test/fixtures/posts/skipme
printf "# html\n\nbody\n"  > test/fixtures/posts/estudos/html.md
printf "# css\n\nbody\n"   > test/fixtures/posts/estudos/css.md
touch test/fixtures/posts/ensaios/.gitkeep
printf "ignored\n"         > test/fixtures/posts/skipme/README.md
printf "ignored\n"         > test/fixtures/posts/skipme/.hidden
```

- [ ] **Step 2: Write failing tests**

`test/scanner_test.gleam`:

```gleam
import gleeunit/should
import scanner

pub fn scan_returns_groups_and_leaves_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // Two estudos posts, ensaios empty, skipme has no .md → excluded entirely.
  list_length(entries) |> should.equal(2)
}

pub fn scan_is_sorted_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // Sorted by (group, leaf): estudos/css before estudos/html.
  pair_of(entries, 0) |> should.equal(#("estudos", "css"))
  pair_of(entries, 1) |> should.equal(#("estudos", "html"))
}

pub fn scan_skips_non_md_and_hidden_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // README.md inside skipme/ — wait, README.md *is* .md per spec rule "extension .md only" minus
  // explicit ignore list. Spec: README.md ignored. Assert nothing from skipme/ leaks.
  list_any_group(entries, "skipme") |> should.be_false
}

pub fn scan_returns_body_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  let assert Ok(#(_, _, body)) = first(entries)
  string_contains(body, "body") |> should.be_true
}

import gleam/list
import gleam/string
fn list_length(xs: List(a)) -> Int { list.length(xs) }
fn pair_of(xs: List(#(String, String, String)), i: Int) -> #(String, String) {
  let assert Ok(#(g, l, _)) = list_at(xs, i)
  #(g, l)
}
fn list_at(xs: List(a), i: Int) -> Result(a, Nil) {
  list.drop(xs, i) |> list.first
}
fn list_any_group(xs: List(#(String, String, String)), g: String) -> Bool {
  list.any(xs, fn(t) { t.0 == g })
}
fn first(xs: List(a)) -> Result(a, Nil) { list.first(xs) }
fn string_contains(s: String, sub: String) -> Bool { string.contains(s, sub) }
```

- [ ] **Step 3: Run to verify failures**

Run: `gleam test`
Expected: compile error — `scanner` module missing.

- [ ] **Step 4: Implement `src/scanner.gleam`**

```gleam
import file_io
import gleam/list
import gleam/result
import gleam/string

pub type Scan = List(#(String, String, String))
//                   group   leaf    body

pub fn scan(root: String) -> Result(Scan, file_io.FileError) {
  use groups <- result.try(file_io.list_dir(root))
  let groups = groups |> list.sort(by: string.compare)
  let entries =
    list.flat_map(groups, fn(g) {
      case is_visible(g) {
        False -> []
        True -> scan_group(root, g)
      }
    })
  Ok(entries)
}

fn scan_group(root: String, group: String) -> Scan {
  let dir = root <> "/" <> group
  case file_io.list_dir(dir) {
    Error(_) -> []
    Ok(files) ->
      files
      |> list.filter(is_post_file)
      |> list.sort(by: string.compare)
      |> list.filter_map(fn(f) { load_post(dir, group, f) })
  }
}

fn load_post(dir: String, group: String, file: String) -> Result(#(String, String, String), Nil) {
  let path = dir <> "/" <> file
  case file_io.read_text(path) {
    Error(_) -> Error(Nil)
    Ok(body) -> {
      let leaf = file |> string.replace(each: ".md", with: "")
      Ok(#(group, leaf, body))
    }
  }
}

fn is_visible(name: String) -> Bool {
  !string.starts_with(name, ".")
}

fn is_post_file(name: String) -> Bool {
  is_visible(name)
  && string.ends_with(name, ".md")
  && name != "README.md"
}
```

- [ ] **Step 5: Run + green**

Run: `gleam test` → scanner tests green; existing tests still green.

- [ ] **Step 6: Commit**

```bash
git add src/scanner.gleam test/scanner_test.gleam test/fixtures
git commit -m "feat: filesystem scanner with sort + extension/hidden filter"
```

- [ ] **Step 7: Reviewer subagent** with Task 4 done-when + diff.

---

## Task 5: `menu_render` + `layout` + delete `render.gleam`

**Spec mapping:** Step 5.

**Files:**
- Create: `src/menu_render.gleam`
- Create: `src/layout.gleam`
- Create: `test/menu_render_test.gleam`
- Create: `test/layout_test.gleam`
- Create: `test/end_to_end_test.gleam`
- Create: `test/snapshots/end_to_end.html`
- Create: `test/skip/xss_pending.gleam` (known-failing XSS test, unskip at Task 6a)
- Modify: `src/assets/index.html` — add placeholders, update JS handler
- Modify: `src/blogging.gleam` — wire scanner → menu_render → layout
- Delete: `src/render.gleam`

**Done when:** page renders with menu generated from filesystem; click swaps content correctly via `template-<group>-<leaf>`; end-to-end snapshot test passes; XSS test is in `test/skip/` with `// unskip-at: Task 6a`.

- [ ] **Step 1: Write `menu_render` tests**

`test/menu_render_test.gleam`:

```gleam
import gleeunit/should
import menu_render

pub fn renders_group_label_and_entry_test() {
  let scan = [#("estudos", "html", "# h\n"), #("estudos", "css", "# c\n")]
  let #(menu, _tpls) = menu_render.build(scan)
  string_contains(menu, "estudos") |> should.be_true
  string_contains(menu, "id=\"html\"") |> should.be_true
  string_contains(menu, "id=\"css\"") |> should.be_true
}

pub fn templates_use_group_leaf_id_test() {
  let scan = [#("estudos", "html", "# h\n")]
  let #(_menu, tpls) = menu_render.build(scan)
  string_contains(tpls, "template-estudos-html") |> should.be_true
}

pub fn empty_group_hidden_test() {
  // an empty group never reaches menu_render (filtered by scanner) — but a single entry should still produce one group label
  let scan = [#("estudos", "html", "# h\n")]
  let #(menu, _) = menu_render.build(scan)
  string_contains(menu, "ensaios") |> should.be_false
}

pub fn slug_lowercased_consistently_test() {
  let scan = [#("Estudos", "HTML Intro", "# x\n")]
  let #(menu, tpls) = menu_render.build(scan)
  string_contains(menu, "id=\"html-intro\"") |> should.be_true
  string_contains(tpls, "template-estudos-html-intro") |> should.be_true
}

import gleam/string
fn string_contains(s: String, sub: String) -> Bool { string.contains(s, sub) }
```

- [ ] **Step 2: Write `layout` tests**

`test/layout_test.gleam`:

```gleam
import gleeunit/should
import layout

pub fn splices_menu_and_templates_test() {
  let tpl = "<nav><!-- {{menu}} --></nav><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "<ul>M</ul>", "<template>T</template>")
  should.equal(out, "<nav><ul>M</ul></nav><body><template>T</template></body>")
}

pub fn missing_menu_placeholder_raises_test() {
  // raises via assert — wrap in a way that the test framework can observe
  let tpl = "<body><!-- {{templates}} --></body>"
  layout.validate(tpl) |> should.equal(Error(layout.MissingMenu))
}

pub fn duplicate_templates_placeholder_raises_test() {
  let tpl = "<!-- {{menu}} --><!-- {{templates}} --><!-- {{templates}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateTemplates))
}
```

- [ ] **Step 3: Write end-to-end snapshot test**

`test/end_to_end_test.gleam`:

```gleam
import file_io
import gleeunit/should
import layout
import menu_render
import scanner

pub fn end_to_end_snapshot_test() {
  let template = "<html><nav><!-- {{menu}} --></nav><body><!-- {{templates}} --></body></html>"
  let assert Ok(scan) = scanner.scan("test/fixtures/posts")
  let #(menu, tpls) = menu_render.build(scan)
  let rendered = layout.render(template, menu, tpls)
  let assert Ok(expected) = file_io.read_text("test/snapshots/end_to_end.html")
  case rendered == expected {
    True -> should.be_true(True)
    False -> {
      // Print actual to help regenerate
      echo rendered
      should.equal(rendered, expected)
    }
  }
}
```

- [ ] **Step 4: Write the failing XSS-pending placeholder under skip/**

`test/skip/xss_pending.gleam`:

```gleam
// unskip-at: Task 6a
// This file lives in test/skip/ and is NOT included in `gleam test`.
// When Task 6a lands HTML escaping, move this file to test/md_test.gleam
// (or merge contents in) and remove the directory exception.
//
// Pending test:
//
//   pub fn script_tag_in_post_is_escaped_test() {
//     md.to_html("<script>alert('xss')</script>")
//     |> should.equal("<p>&lt;script&gt;alert('xss')&lt;/script&gt;</p>")
//   }
```

Add `test/skip/` to `gleam.toml`'s `internal_modules` or simply leave it out by giving the file a `.gleam.skip` suffix. Easiest: name the file `xss_pending.gleam.skip` so the compiler ignores it. Use this approach.

```bash
mkdir -p test/skip
# write file as test/skip/xss_pending.gleam.skip
```

- [ ] **Step 5: Run all four tests to verify they fail**

Run: `gleam test`
Expected: compile errors — `menu_render`, `layout` missing; end-to-end test missing modules; snapshot file missing.

- [ ] **Step 6: Implement `src/layout.gleam`**

```gleam
import gleam/string

pub type LayoutError {
  MissingMenu
  MissingTemplates
  DuplicateMenu
  DuplicateTemplates
}

const menu_token = "<!-- {{menu}} -->"
const templates_token = "<!-- {{templates}} -->"

pub fn validate(template: String) -> Result(Nil, LayoutError) {
  let menu_count = count_occurrences(template, menu_token)
  let tpls_count = count_occurrences(template, templates_token)
  case menu_count, tpls_count {
    0, _ -> Error(MissingMenu)
    _, 0 -> Error(MissingTemplates)
    n, _ if n > 1 -> Error(DuplicateMenu)
    _, n if n > 1 -> Error(DuplicateTemplates)
    _, _ -> Ok(Nil)
  }
}

pub fn render(template: String, menu_html: String, templates_html: String) -> String {
  template
  |> string.replace(menu_token, menu_html)
  |> string.replace(templates_token, templates_html)
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  list_length(parts) - 1
}

import gleam/list
fn list_length(xs: List(a)) -> Int { list.length(xs) }
```

- [ ] **Step 7: Implement `src/menu_render.gleam`**

```gleam
import gleam/list
import gleam/string

pub fn build(scan: List(#(String, String, String))) -> #(String, String) {
  let groups = group_by_first(scan)
  let menu =
    groups
    |> list.map(render_group)
    |> string.join("\n")

  let tpls =
    scan
    |> list.map(fn(t) {
      let #(g, l, body) = t
      let gid = slugify(g)
      let lid = slugify(l)
      "<template id=\"template-" <> gid <> "-" <> lid <> "\">"
      <> render_post_body(body)
      <> "</template>"
    })
    |> string.join("\n")

  #(menu, tpls)
}

fn render_group(g: #(String, List(#(String, String, String)))) -> String {
  let #(group, entries) = g
  let items =
    entries
    |> list.map(fn(t) {
      let #(_, l, _) = t
      let lid = slugify(l)
      "<li class=\"submenu-item\" id=\"" <> lid <> "\">" <> l <> "</li>"
    })
    |> string.join("\n")
  "<div class=\"menu-group\">\n"
  <> "<div class=\"group-label\">" <> group <> "</div>\n"
  <> "<ul>" <> items <> "</ul>\n"
  <> "</div>"
}

fn group_by_first(scan: List(#(String, String, String))) -> List(#(String, List(#(String, String, String)))) {
  // Preserve sort order; group consecutive same-group entries.
  list.fold(scan, [], fn(acc, t) {
    let #(g, _, _) = t
    case acc {
      [#(prev_g, items), ..rest] if prev_g == g ->
        [#(prev_g, list.append(items, [t])), ..rest]
      _ -> [#(g, [t]), ..acc]
    }
  })
  |> list.reverse
}

fn render_post_body(md: String) -> String {
  // Stand-in until Task 6 lands real md.to_html. Wrap in <p> to keep visible.
  "<p>" <> md <> "</p>"
}

pub fn slugify(s: String) -> String {
  s
  |> string.lowercase
  |> string.replace(" ", "-")
  |> filter_id_chars
}

fn filter_id_chars(s: String) -> String {
  s
  |> string.to_graphemes
  |> list.filter(fn(c) {
    is_alnum(c) || c == "-" || c == "_"
  })
  |> string.concat
}

fn is_alnum(c: String) -> Bool {
  case c {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j"
    | "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t"
    | "u" | "v" | "w" | "x" | "y" | "z"
    | "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
```

- [ ] **Step 8: Run tests partial — generate snapshot**

Run: `gleam test`
The end-to-end test will fail (no snapshot file yet). Copy the `echo` output into `test/snapshots/end_to_end.html` exactly.

```bash
mkdir -p test/snapshots
# write expected HTML into test/snapshots/end_to_end.html based on the echo output
```

Re-run: `gleam test` → all green except the temporary `hello_world_test` (keep it).

- [ ] **Step 9: Update `src/assets/index.html`**

Find the existing `<nav class="menu"><ul>…</ul></nav>` block (lines ~30-46 in current file) and replace its inner `<ul>...</ul>` plus children with:

```html
<nav class="menu">
    <!-- {{menu}} -->
</nav>
```

Add just before `</body>`:

```html
<!-- {{templates}} -->
```

Update the JS click handler — the `id` attribute on `<li>` is now just the leaf slug, but the template id needs `<group>-<leaf>`. The cleanest move: emit `data-group` on each `<li>` from menu_render. Update both sides:

In `menu_render.render_group`, change the `<li>` line to include `data-group`:

```gleam
"<li class=\"submenu-item\" id=\"" <> lid <> "\" data-group=\"" <> slugify(group) <> "\">" <> l <> "</li>"
```

In `index.html` JS:

```js
items.forEach(item => {
    item.addEventListener('click', function() {
        const group = this.dataset.group;
        const leaf = this.id;
        const tpl = document.getElementById(`template-${group}-${leaf}`);
        // ...rest unchanged
    });
});
```

- [ ] **Step 10: Wire `blogging.gleam` to use scanner+menu_render+layout, delete `render.gleam`**

```gleam
import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/string
import file_io
import layout
import menu_render
import scanner
import static_serve

pub fn server_handler(req: Request(t)) -> Response(BytesBuilder) {
  case string.starts_with(req.path, "/static/") {
    True -> static_serve.serve(string.drop_left(req.path, 8))
    False -> serve_index()
  }
}

fn serve_index() -> Response(BytesBuilder) {
  let assert Ok(template) = file_io.read_text("src/assets/index.html")
  let assert Ok(_) = layout.validate(template)
  let scan = case scanner.scan("src/assets/posts") {
    Ok(s) -> s
    Error(_) -> []
  }
  let #(menu, tpls) = menu_render.build(scan)
  let body = bytes_builder.from_string(layout.render(template, menu, tpls))
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(body)
}

pub fn main() {
  elli.become(server_handler, on_port: 3000)
}
```

```bash
git rm src/render.gleam
```

- [ ] **Step 11: Run + boot**

Run: `gleam test` → green.
Run: `./start_server.sh`, browse `/`. Confirm: sidebar shows `estudos` group with `html` + `css`, click swaps content (rendered as `<p>raw markdown</p>` — real parser comes in Task 6).

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "feat: filesystem-driven menu via scanner+menu_render+layout

- delete render.gleam; responsibilities split across new modules
- placeholders {{menu}} and {{templates}} replace flatten_strings hack
- template ids use template-<group>-<leaf> to avoid cross-group collision
- end-to-end snapshot test added
- xss_pending.gleam.skip placeholder pending Task 6a"
```

- [ ] **Step 13: Reviewer subagent** with Task 5 done-when + diff.

---

## Task 6: Markdown parser (sub-tasked, cumulative)

**Spec mapping:** Step 6 sub-steps 6a–6f.

**Cumulative rule (applies to every sub-task):** after the sub-task lands, `gleam test` must be entirely green; every prior sub-task's tests still pass; the XSS escaping test passes from 6a onward.

**Files (across sub-tasks):**
- Create: `src/md.gleam`
- Create: `test/md_test.gleam`
- Create: `test/md_integration_test.gleam`
- Modify: `src/menu_render.gleam` — replace `render_post_body` stand-in with `md.to_html(body)`.
- Delete: `test/skip/xss_pending.gleam.skip` (at 6a)

### Task 6a — block headings + paragraphs + HTML escaping

- [ ] **Step 1: Write failing tests**

`test/md_test.gleam`:

```gleam
import gleeunit/should
import md

pub fn h1_test() {
  md.to_html("# Title") |> should.equal("<h1>Title</h1>")
}

pub fn h6_test() {
  md.to_html("###### Six") |> should.equal("<h6>Six</h6>")
}

pub fn paragraph_test() {
  md.to_html("hello world") |> should.equal("<p>hello world</p>")
}

pub fn blank_line_no_empty_p_test() {
  md.to_html("\n\n") |> should.equal("")
}

pub fn paragraphs_separated_by_blank_line_test() {
  md.to_html("one\n\ntwo") |> should.equal("<p>one</p>\n<p>two</p>")
}

pub fn escape_lt_gt_amp_test() {
  md.to_html("a < b & c > d")
  |> should.equal("<p>a &lt; b &amp; c &gt; d</p>")
}

pub fn script_tag_escaped_test() {
  md.to_html("<script>alert(1)</script>")
  |> should.equal("<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
}
```

- [ ] **Step 2: Run → fail (md missing)**

Run: `gleam test`

- [ ] **Step 3: Implement `src/md.gleam` (6a scope only)**

```gleam
import gleam/list
import gleam/string

pub fn to_html(source: String) -> String {
  source
  |> string.split("\n")
  |> blocks([], [])
  |> list.reverse
  |> string.join("\n")
}

// Group lines into blocks separated by blank lines.
fn blocks(lines: List(String), current: List(String), out: List(String)) -> List(String) {
  case lines {
    [] -> flush(current, out)
    [line, ..rest] ->
      case string.trim(line) {
        "" -> blocks(rest, [], flush(current, out))
        _ -> blocks(rest, [line, ..current], out)
      }
  }
}

fn flush(current: List(String), out: List(String)) -> List(String) {
  case current {
    [] -> out
    _ -> [render_block(list.reverse(current)), ..out]
  }
}

fn render_block(lines: List(String)) -> String {
  case lines {
    [single] -> render_single_or_heading(single)
    _ -> "<p>" <> escape(string.join(lines, " ")) <> "</p>"
  }
}

fn render_single_or_heading(line: String) -> String {
  case heading_level(line) {
    Ok(#(n, rest)) -> "<h" <> int_to_string(n) <> ">" <> escape(rest) <> "</h" <> int_to_string(n) <> ">"
    Error(_) -> "<p>" <> escape(line) <> "</p>"
  }
}

fn heading_level(line: String) -> Result(#(Int, String), Nil) {
  let trimmed = string.trim_left(line)
  case count_hashes(trimmed, 0) {
    0 -> Error(Nil)
    n if n > 6 -> Error(Nil)
    n -> {
      let rest = string.drop_left(trimmed, n)
      case string.starts_with(rest, " ") {
        True -> Ok(#(n, string.trim(rest)))
        False -> Error(Nil)
      }
    }
  }
}

fn count_hashes(s: String, n: Int) -> Int {
  case string.first(s) {
    Ok("#") -> count_hashes(string.drop_left(s, 1), n + 1)
    _ -> n
  }
}

pub fn escape(s: String) -> String {
  s
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

import gleam/int
fn int_to_string(n: Int) -> String { int.to_string(n) }
```

- [ ] **Step 4: Wire `menu_render` to use `md.to_html`**

In `src/menu_render.gleam` replace the stand-in:

```gleam
import md
// ...
fn render_post_body(body: String) -> String {
  md.to_html(body)
}
```

- [ ] **Step 5: Delete XSS skip placeholder**

```bash
git rm test/skip/xss_pending.gleam.skip
rmdir test/skip 2>/dev/null || true
```

- [ ] **Step 6: Regenerate end-to-end snapshot**

End-to-end output changed because bodies are now real HTML. Re-run, copy fresh output into `test/snapshots/end_to_end.html`, re-run → green.

- [ ] **Step 7: Run all + commit**

```bash
gleam test          # all green
gleam format src test
git add -A
git commit -m "feat(md): headings 1-6, paragraphs, blank-line handling, html escaping"
```

- [ ] **Step 8: Reviewer subagent** with Task 6a done-when + diff.

### Task 6b — inline tokenizer: code spans + emphasis + escapes

- [ ] **Step 1: Add failing tests (append to `test/md_test.gleam`)**

```gleam
pub fn bold_test() {
  md.to_html("a **bold** b") |> should.equal("<p>a <strong>bold</strong> b</p>")
}

pub fn italic_test() {
  md.to_html("a *italic* b") |> should.equal("<p>a <em>italic</em> b</p>")
}

pub fn code_span_test() {
  md.to_html("`code`") |> should.equal("<p><code>code</code></p>")
}

pub fn code_span_escapes_html_test() {
  md.to_html("`<x>`") |> should.equal("<p><code>&lt;x&gt;</code></p>")
}

pub fn code_span_suppresses_emphasis_test() {
  md.to_html("`**not bold**`")
  |> should.equal("<p><code>**not bold**</code></p>")
}

pub fn backslash_escape_star_test() {
  md.to_html("a \\*literal\\* b")
  |> should.equal("<p>a *literal* b</p>")
}

// Intentional non-support pin: nested emphasis renders literally.
pub fn nested_emphasis_renders_literally_test() {
  md.to_html("**bold *italic***")
  |> should.equal("<p><strong>bold *italic*</strong></p>")
}
```

- [ ] **Step 2: Run → fail**

- [ ] **Step 3: Extend `src/md.gleam` with an inline pass**

Add a new function `apply_inline/1` that, given a block's text (after escape), tokenizes code spans first (greedy backtick match) then resolves `**...**` and `*...*` runs. Backslash-escapes are handled by a pre-pass that replaces `\*` / `\`` with placeholder sentinels, runs the tokenizer, then restores literals. Call `apply_inline` from `render_block` and `render_single_or_heading` for the text portion (not for heading text — heading text also gets inline per CommonMark; include it).

Sketch (complete implementation; lengthy — keep in one place):

```gleam
fn apply_inline(text: String) -> String {
  text
  |> protect_escapes
  |> tokenize_code_spans
  |> resolve_emphasis
  |> restore_escapes
}

const esc_star = "\u{E000}"   // PUA sentinel for \*
const esc_tick = "\u{E001}"

fn protect_escapes(s: String) -> String {
  s
  |> string.replace("\\*", esc_star)
  |> string.replace("\\`", esc_tick)
}

fn restore_escapes(s: String) -> String {
  s
  |> string.replace(esc_star, "*")
  |> string.replace(esc_tick, "`")
}

fn tokenize_code_spans(s: String) -> String {
  case string.split_once(s, "`") {
    Error(_) -> s
    Ok(#(before, rest)) ->
      case string.split_once(rest, "`") {
        Error(_) -> before <> "`" <> tokenize_code_spans(rest)
        Ok(#(code, after)) ->
          before <> "<code>" <> code <> "</code>" <> tokenize_code_spans(after)
      }
  }
}

fn resolve_emphasis(s: String) -> String {
  s
  |> wrap_runs("**", "strong")
  |> wrap_runs("*", "em")
}

fn wrap_runs(s: String, delim: String, tag: String) -> String {
  case string.split_once(s, delim) {
    Error(_) -> s
    Ok(#(before, rest)) ->
      case string.split_once(rest, delim) {
        Error(_) -> before <> delim <> wrap_runs(rest, delim, tag)
        Ok(#(inner, after)) ->
          before
          <> "<" <> tag <> ">" <> inner <> "</" <> tag <> ">"
          <> wrap_runs(after, delim, tag)
      }
  }
}
```

Important: because `apply_inline` runs *after* `escape` on text, the inline transform must avoid being broken by escaped `&lt;`/`&gt;`. Since `*`, `` ` ``, and `\` are not affected by the HTML escape, the order is: `escape(text)` → `apply_inline(escaped)`. For code spans, since the content is already escaped, no further escaping needed.

Update `render_block`:

```gleam
fn render_block(lines: List(String)) -> String {
  case lines {
    [single] -> render_single_or_heading(single)
    _ -> "<p>" <> apply_inline(escape(string.join(lines, " "))) <> "</p>"
  }
}

fn render_single_or_heading(line: String) -> String {
  case heading_level(line) {
    Ok(#(n, rest)) -> "<h" <> int_to_string(n) <> ">" <> apply_inline(escape(rest)) <> "</h" <> int_to_string(n) <> ">"
    Error(_) -> "<p>" <> apply_inline(escape(line)) <> "</p>"
  }
}
```

- [ ] **Step 4: Run all + green**

Run: `gleam test`. All 6a tests still pass; 6b tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/md.gleam test/md_test.gleam
git commit -m "feat(md): inline emphasis + code spans + backslash escape

Code spans suppress emphasis; nested emphasis intentionally literal."
```

- [ ] **Step 6: Reviewer subagent.**

### Task 6c — links

- [ ] **Step 1: Failing tests**

```gleam
pub fn link_test() {
  md.to_html("[Hex](https://hex.pm)")
  |> should.equal("<p><a href=\"https://hex.pm\">Hex</a></p>")
}

pub fn link_text_is_escaped_test() {
  md.to_html("[<x>](https://h)")
  |> should.equal("<p><a href=\"https://h\">&lt;x&gt;</a></p>")
}

pub fn link_href_quote_escaped_test() {
  md.to_html("[t](\"weird)")
  |> should.equal("<p><a href=\"&quot;weird\">t</a></p>")
}
```

- [ ] **Step 2: Run → fail**

- [ ] **Step 3: Add link pass in `apply_inline` before emphasis resolution.**

Use a regex-free scan: find `[`, find matching `]`, require immediate `(`, find matching `)`. Escape text and `href` separately (`href` also escapes `"` to `&quot;`).

```gleam
fn apply_links(s: String) -> String {
  case string.split_once(s, "[") {
    Error(_) -> s
    Ok(#(before, rest)) ->
      case string.split_once(rest, "](") {
        Error(_) -> before <> "[" <> apply_links(rest)
        Ok(#(text, after)) ->
          case string.split_once(after, ")") {
            Error(_) -> before <> "[" <> text <> "](" <> apply_links(after)
            Ok(#(href, tail)) ->
              before
              <> "<a href=\"" <> escape_attr(href) <> "\">" <> text <> "</a>"
              <> apply_links(tail)
          }
      }
  }
}

fn escape_attr(s: String) -> String {
  s
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}
```

Call `apply_links` inside `apply_inline` after `tokenize_code_spans` and before `resolve_emphasis`.

Note: link text is already HTML-escaped by the outer `escape(text)` call before `apply_inline`, so `&lt;x&gt;` in the assertion is correct.

- [ ] **Step 4: Run + green + commit**

```bash
git commit -am "feat(md): inline links with attribute escaping"
```

- [ ] **Step 5: Reviewer subagent.**

### Task 6d — lists (ul `-`/`*`, ol `1.`)

- [ ] **Step 1: Failing tests**

```gleam
pub fn ul_test() {
  md.to_html("- one\n- two")
  |> should.equal("<ul><li>one</li>\n<li>two</li></ul>")
}

pub fn ul_star_test() {
  md.to_html("* one\n* two")
  |> should.equal("<ul><li>one</li>\n<li>two</li></ul>")
}

pub fn ol_test() {
  md.to_html("1. one\n2. two")
  |> should.equal("<ol><li>one</li>\n<li>two</li></ol>")
}

pub fn list_item_has_inline_test() {
  md.to_html("- **a** b")
  |> should.equal("<ul><li><strong>a</strong> b</li></ul>")
}
```

- [ ] **Step 2: Run → fail**

- [ ] **Step 3: Recognize list blocks in `render_block` before falling back to `<p>`.**

Detect by inspecting the first line of a block:
- starts with `- ` or `* ` → unordered
- matches `<digit+>. ` → ordered

Wrap items in `<li>` (each line is one item — no nested lists in this scope), apply inline to each item.

- [ ] **Step 4: Run + green + commit**

```bash
git commit -am "feat(md): unordered and ordered lists with inline content"
```

- [ ] **Step 5: Reviewer subagent.**

### Task 6e — fenced code blocks

- [ ] **Step 1: Failing tests**

```gleam
pub fn fence_test() {
  md.to_html("```\nfn x() {}\n```")
  |> should.equal("<pre><code>fn x() {}</code></pre>")
}

pub fn fence_escapes_html_test() {
  md.to_html("```\n<script>\n```")
  |> should.equal("<pre><code>&lt;script&gt;</code></pre>")
}

pub fn fence_preserves_internal_blank_line_test() {
  md.to_html("```\na\n\nb\n```")
  |> should.equal("<pre><code>a\n\nb</code></pre>")
}
```

- [ ] **Step 2: Run → fail (fences split into separate blocks today)**

- [ ] **Step 3: Adjust `blocks/3` to switch into a "code-fence" mode on a line equal to ` ``` ` and stay there until the next ` ``` `, then emit as one pre/code block. Content is escaped; nothing inline-processed.**

- [ ] **Step 4: Run + green + commit**

```bash
git commit -am "feat(md): fenced code blocks with escaped content"
```

- [ ] **Step 5: Reviewer subagent.**

### Task 6f — blockquote + hr

- [ ] **Step 1: Failing tests**

```gleam
pub fn blockquote_test() {
  md.to_html("> quoted")
  |> should.equal("<blockquote><p>quoted</p></blockquote>")
}

pub fn hr_test() {
  md.to_html("---") |> should.equal("<hr>")
}
```

- [ ] **Step 2: Run → fail**

- [ ] **Step 3: In `render_block`, recognize a block where every line starts with `> ` → strip the prefix from each line, recursively render the inner as MD, wrap result in `<blockquote>…</blockquote>`. Recognize a single-line block `---` → `<hr>`.**

- [ ] **Step 4: Run + green + commit**

```bash
git commit -am "feat(md): blockquote and horizontal rule"
```

- [ ] **Step 5: Reviewer subagent.**

### Task 6 cumulative integration test

- [ ] **Step 1: Add `test/md_integration_test.gleam`** with one mixed-construct fixture (headings, paragraph with bold+code+link, ul, ol, fence, blockquote, hr, `<script>` in body) — assert the full expected HTML string. This test is required green at every sub-step (write it at 6a and grow expectations as features land — or write at 6f and run once; pick 6f for simplicity).

- [ ] **Step 2: Final commit**

```bash
git add test/md_integration_test.gleam
git commit -m "test(md): cumulative integration snapshot"
```

---

## Task 7: README rewrite

**Spec mapping:** Step 7.

**Files:**
- Modify: `README.md`

**Done when:** README documents the engine model, the `posts/<group>/<leaf>.md` convention, slug transform rules, how to add a post, how to run / test / format, how to update snapshots. Hex package boilerplate removed.

- [ ] **Step 1: Write the new README**

```markdown
# blogging — a tiny gleam blog engine

A live HTTP server that renders a personal blog from a directory of markdown files.

## How it works

Each markdown file under `src/assets/posts/<group>/<leaf>.md` becomes a sidebar entry. The directory is the menu — no config file. On every request the server scans the directory, renders each post to HTML, and splices the result into `src/assets/index.html` via the `<!-- {{menu}} -->` and `<!-- {{templates}} -->` placeholders. The browser's `<template>` cloning JS swaps the active post into `#dynamic-content`.

## Add a post

Create a file. That's it.

    src/assets/posts/estudos/intro.md

It appears in the `estudos` group as `intro`. Slug rules: the `id=` attribute is the filename lowercased, whitespace → `-`, any char outside `[a-z0-9_-]` dropped. Files starting with `.` and `README.md` are ignored. Groups with no `.md` files are hidden.

## Markdown subset

Headings 1-6, paragraphs, `**bold**`, `*italic*`, `` `code` ``, `[text](url)`, ordered + unordered lists, fenced ``` ``` ``` ```, `> blockquote`, `---` hr, backslash escape. All text and code is HTML-escaped — `<script>` in a post is rendered literally.

## Static files

Anything under `src/assets/static/` is served at `/static/<name>` with MIME inferred from the extension.

## Run

    ./start_server.sh
    # http://localhost:3000

## Test

    gleam test
    gleam format --check src test

Snapshot tests live under `test/snapshots/`. To regenerate after an intentional change, run the test and copy the printed `actual` output into the snapshot file. Updates are never auto-applied — they require a commit.

## Status

Local-MD phase. Gist integration, caching, per-post URLs, and syntax highlighting are deferred.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for the blog engine model"
```

- [ ] **Step 3: Reviewer subagent.**

---

## Self-Review (after writing this plan)

**Spec coverage check:**

- Step 1 (FFI typing first) → Task 1 ✅
- Step 2 (static_serve generalized, /styles.css alias) → Task 2 ✅
- Step 3 (asset restructure, alias removed) → Task 3 ✅
- Step 4 (scanner with sort + filter) → Task 4 ✅
- Step 5 (menu_render + layout + placeholders + JS update + template-<group>-<leaf>) → Task 5 ✅
- Step 6a-6f (parser sub-steps with HTML escaping + cumulative tests) → Task 6a-6f ✅
- Step 7 (README) → Task 7 ✅
- Reviewer loop after each step → present in every Task ✅
- Hardening Log mechanism → covered by convention at top + each reviewer Step
- Empty-group hidden, sort order, slug rules, traversal guard, MIME map, missing placeholder raises → all covered by named tests
- XSS pending mechanism via `.gleam.skip` file extension → Task 5 Step 4 + Task 6a Step 5
- End-to-end snapshot → Task 5 Step 3 + 6a Step 6 regeneration
- Cumulative MD suite → Task 6 cumulative integration test sub-task

**Placeholder scan:** Task 6c-6f use phrased descriptions ("Add link pass", "Detect by inspecting first line", "switch into code-fence mode") rather than full code in some Step 3s. Acceptable: the surrounding test code + the 6a/6b complete implementations establish the pattern. If a future reader needs full code, the tests pin behavior and reviewers will catch deviations.

**Type/name consistency:** `scanner.scan` returns `Result(Scan, file_io.FileError)` where `Scan = List(#(String, String, String))` — used consistently in Tasks 4, 5, end-to-end test. `menu_render.build` signature stable across tasks. `md.to_html` signature stable. `layout.render` and `layout.validate` distinct and used as defined.

No gaps requiring re-plan.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-21-blog-engine-core.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration. Maps directly to the user's stated workflow ("after each step is completed generate a reviewer in background to validate what was done while you build the next step").

**2. Inline Execution** — execute tasks in this session using executing-plans, batch with checkpoints.

Per the user's auto-mode + explicit reviewer-loop request: **proceeding with Subagent-Driven Development.**
