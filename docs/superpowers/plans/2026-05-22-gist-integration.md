# Gist Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the local-MD source with a live GitHub Gists source. Posts are discovered by filename pattern `blog:<group>:<leaf>.md` across the configured user's public gists, fetched on every request (no cache), with a sidebar banner shown when GitHub is unreachable. Status stays 200 on failure.

**Architecture:** Add one new module `gist` that owns the `Post` type, the discovery convention, and an `HttpClient` capability (injectable for tests). `layout` learns a third placeholder `<!-- {{banner}} -->`. `menu_render` migrates its `Post` import from `scanner` to `gist`. `blogging.gleam` reads `BLOG_GIST_USER` at boot, does per-request `gist.fetch_all → menu_render.build → layout.render`, with a 15 s whole-handler timeout cap, and renders an empty menu plus the banner on any `GistError`. `scanner.gleam` and the on-disk `posts/` tree are deleted in the last task.

**Tech Stack:** Gleam 1.16.0, Erlang/OTP 26, Elli, gleeunit, new deps `gleam_httpc` and `gleam_json`.

**Spec:** `docs/superpowers/specs/2026-05-22-gist-integration-design.md`

**Branch:** `feat/gist-integration` — single branch, no per-task branches, no stacked PRs.

**Reviewer loop:** after each Task completes, dispatch a background subagent with the spec + that task's Done-when + the git diff. Blocker/major findings get fixed before the next Task. Append a one-line lesson to the spec's Hardening Log only if it leads to a future-step convention or test.

---

## File Map

**New:**
- `src/gist.gleam` — `Post`, `GistError`, `HttpClient`, private `parse_filename`, `fetch_all`, `live_client`
- `test/gist_test.gleam` — unit + integration tests (filename matcher, URL building, JSON parse, collision rule, Ok/Error/partial paths)
- `test/fixtures/gist_list.json` — canned `/users/<user>/gists` response
- `test/fixtures/gist_raw/blog_estudos_html.md` and friends — canned raw bodies

**Modified:**
- `gleam.toml` — add `gleam_httpc`, `gleam_json` (+ transitive `gleam_dynamic`)
- `src/layout.gleam` — banner token in `validate` + third arg in `render`
- `src/assets/index.html` — `<!-- {{banner}} -->` inside `.sidebar`, below `<nav class="menu">`
- `src/assets/static/styles.css` — `.error-banner` rule
- `src/menu_render.gleam` — `import gist` instead of `import scanner` (one-line change)
- `src/blogging.gleam` — boot reads env var; handler does per-request fetch+render with 15 s cap; logs errors
- `docker-compose.yml` — `environment: BLOG_GIST_USER: Yuhigawa`
- `test/layout_test.gleam` — updated for 3-arg `render` + new banner validation errors
- `test/menu_render_test.gleam` — `import gist` instead of `import scanner` (Post constructor moves)
- `test/end_to_end_test.gleam` — fixture switches from on-disk scan to inline `List(gist.Post)`
- `test/snapshots/end_to_end.html` — re-generated against the new fixture and the banner-aware template
- `README.md` — drop the filesystem-scan section, document `BLOG_GIST_USER` + the `blog:<group>:<leaf>.md` convention

**Deleted (in Task 7 only):**
- `src/scanner.gleam`
- `test/scanner_test.gleam`
- `test/fixtures/posts/` (entire subtree)
- `src/assets/posts/` (entire subtree)

---

## Conventions used in every task

**TDD cadence:** write failing test → run to confirm RED → minimal impl → run to confirm GREEN → commit.

**Toolchain (everything runs in Docker):**
- All tests: `docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test`
- Format check: `docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format --check src test`
- Format apply: `docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format src test`
- Add a dep: `docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam add <pkg>`
- Boot server: `docker compose up blogging` (port 3000)
- Single test: gleeunit has no native filter; run the whole suite and grep the output.

**Commit format:** `feat(<scope>): <what>` for new behavior, `refactor(<scope>): <what>` for moves, `test(<scope>): <what>` for test-only commits, `chore: <what>` for build/deps/docs. Never include `Co-Authored-By` trailers in any commit messages.

**Branch:** every commit lands on `feat/gist-integration`.

---

## Task 1: Setup — deps, `Post`/`GistError` types, `menu_render` import migration

**Spec mapping:** Phasing step 1.

**Files:**
- Modify: `gleam.toml`
- Create: `src/gist.gleam`
- Modify: `src/menu_render.gleam`
- Modify: `test/menu_render_test.gleam`

**Done when:**
- `gleam.toml` has `gleam_httpc` and `gleam_json` in `[dependencies]`; `gleam deps download` succeeds; `manifest.toml` updated.
- `src/gist.gleam` exports `Post(group: String, leaf: String, body: String)`, `GistError`, and an `HttpClient` type stub. No `fetch_all` body yet (or a stubbed one that returns `Error(NetworkError("not implemented"))`).
- `menu_render` and its test import `gist.Post` instead of `scanner.Post`.
- `scanner.gleam` and `scanner_test.gleam` still exist and still compile (we removed the only production consumer, but `blogging.gleam` still calls `scanner.scan` at boot).
- `gleam test` green; `gleam format --check src test` green.

- [ ] **Step 1: Add the deps**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam add gleam_httpc
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam add gleam_json
```

Expected: `gleam.toml` `[dependencies]` gains both entries; `manifest.toml` regenerated (committed).

- [ ] **Step 2: Write the failing import-migration test (no new test — just change the existing one)**

Edit `test/menu_render_test.gleam`. Replace `import scanner` with `import gist` and replace every `scanner.Post(...)` with `gist.Post(...)`. Run:

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

Expected: compile error — `gist` module does not exist yet (or has no `Post`).

- [ ] **Step 3: Create `src/gist.gleam` with the minimal types**

```gleam
pub type Post {
  Post(group: String, leaf: String, body: String)
}

pub type GistError {
  NetworkError(reason: String)
  HttpError(status: Int)
  ParseError(reason: String)
}

pub type HttpClient {
  HttpClient(
    list_gists: fn(String) -> Result(String, GistError),
    fetch_raw: fn(String) -> Result(String, GistError),
  )
}

/// Stub. Real implementation lands in Task 4 (fake client) and Task 5 (live client).
pub fn fetch_all(
  _client: HttpClient,
  _user: String,
) -> Result(List(Post), GistError) {
  Error(NetworkError("not implemented"))
}
```

- [ ] **Step 4: Migrate `src/menu_render.gleam` import**

In `src/menu_render.gleam`:

```gleam
// before:
import scanner
// after:
import gist

// before:
pub fn build(scan: List(scanner.Post)) -> #(String, String) {
// after:
pub fn build(scan: List(gist.Post)) -> #(String, String) {

// before:
fn render_group(g: #(String, List(scanner.Post))) -> String {
// after:
fn render_group(g: #(String, List(gist.Post))) -> String {

// before:
fn group_by_first(
  scan: List(scanner.Post),
) -> List(#(String, List(scanner.Post))) {
// after:
fn group_by_first(
  scan: List(gist.Post),
) -> List(#(String, List(gist.Post))) {
```

(Exactly one production module — `menu_render` — references `scanner.Post`. Migrate all four occurrences in one pass.)

- [ ] **Step 5: Confirm `blogging.gleam` and `end_to_end_test.gleam` still compile**

`blogging.gleam` uses `scanner.scan(...)` and passes its result to `menu_render.build`. Because `scanner.Post` and `gist.Post` now have **identical shape** but are **distinct nominal types**, the call site will fail to compile.

Fix by inlining a one-liner translation in `src/blogging.gleam` — keep `scanner` doing the disk walk, but map its records to `gist.Post` before handing off to `menu_render`:

```gleam
// in main(), after the existing `let assert Ok(scan) = scanner.scan(...)`:
let scan =
  scan
  |> list.map(fn(p) {
    let scanner.Post(group: g, leaf: l, body: b) = p
    gist.Post(group: g, leaf: l, body: b)
  })
```

Add `import gist` and `import gleam/list` at the top of `src/blogging.gleam` if not already present.

Apply the same one-liner translation in `test/end_to_end_test.gleam` so the snapshot test continues to pass:

```gleam
// after `let assert Ok(scan) = scanner.scan(...)`:
let scan =
  scan
  |> list.map(fn(p) {
    let scanner.Post(group: g, leaf: l, body: b) = p
    gist.Post(group: g, leaf: l, body: b)
  })
```

- [ ] **Step 6: Run tests and format**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format --check src test
```

Expected: all tests pass (same count as before); format check passes.

- [ ] **Step 7: Commit**

```bash
git add gleam.toml manifest.toml src/gist.gleam src/menu_render.gleam src/blogging.gleam test/menu_render_test.gleam test/end_to_end_test.gleam
git commit -m "feat(gist): introduce gist module with Post/GistError/HttpClient types

Add gleam_httpc + gleam_json deps. menu_render now consumes gist.Post.
blogging.gleam still calls scanner.scan at boot and translates to gist.Post
inline; scanner stays alive as the data source until Task 6."
```

---

## Task 2: Banner token in `layout`, `index.html`, and styles

**Spec mapping:** Phasing step 2.

**Files:**
- Modify: `src/layout.gleam`
- Modify: `test/layout_test.gleam`
- Modify: `src/assets/index.html`
- Modify: `src/assets/static/styles.css`
- Modify: `src/blogging.gleam` (3-arg call site)
- Modify: `test/end_to_end_test.gleam` (3-arg call site)
- Modify: `test/snapshots/end_to_end.html` (regenerate after adding the token)

**Done when:**
- `layout.validate` rejects templates missing `<!-- {{banner}} -->`, present zero or >1 times.
- `layout.render(template, menu, tpls, banner)` substitutes all three tokens.
- `src/assets/index.html` has `<!-- {{banner}} -->` inside `<aside class="sidebar">`, below `<nav class="menu">`.
- `.error-banner` CSS exists in `src/assets/static/styles.css`.
- `gleam test` green, `gleam format --check src test` green.

- [ ] **Step 1: Write the failing validate tests**

In `test/layout_test.gleam`, **add** (don't replace) these tests:

```gleam
pub fn missing_banner_placeholder_raises_test() {
  let tpl = "<!-- {{menu}} --><!-- {{templates}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.MissingBanner))
}

pub fn duplicate_banner_placeholder_raises_test() {
  let tpl =
    "<!-- {{menu}} --><!-- {{templates}} --><!-- {{banner}} --><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateBanner))
}

pub fn render_substitutes_banner_test() {
  let tpl =
    "<nav><!-- {{menu}} --></nav><div><!-- {{banner}} --></div><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "M", "T", "BAN")
  should.equal(out, "<nav>M</nav><div>BAN</div><body>T</body>")
}

pub fn render_empty_banner_collapses_test() {
  let tpl =
    "<nav><!-- {{menu}} --></nav><div><!-- {{banner}} --></div><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "M", "T", "")
  should.equal(out, "<nav>M</nav><div></div><body>T</body>")
}
```

Also update the existing `splices_menu_and_templates_test` to call the new 4-arg `render` and validate a template that includes `<!-- {{banner}} -->`:

```gleam
pub fn splices_menu_and_templates_test() {
  let tpl =
    "<nav><!-- {{menu}} --></nav><div><!-- {{banner}} --></div><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "<ul>M</ul>", "<template>T</template>", "")
  should.equal(
    out,
    "<nav><ul>M</ul></nav><div></div><body><template>T</template></body>",
  )
}
```

The existing `missing_menu_placeholder_raises_test` and `missing_templates_placeholder_raises_test` may need their fixture templates extended to include the other two tokens — what they assert about menu/templates absence must remain testable independently. Update each to include the other two valid tokens, so only the asserted-missing token is absent:

```gleam
pub fn missing_menu_placeholder_raises_test() {
  let tpl = "<body><!-- {{templates}} --></body><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.MissingMenu))
}

pub fn missing_templates_placeholder_raises_test() {
  let tpl = "<nav><!-- {{menu}} --></nav><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.MissingTemplates))
}

pub fn duplicate_menu_placeholder_raises_test() {
  let tpl =
    "<!-- {{menu}} --><!-- {{menu}} --><!-- {{templates}} --><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateMenu))
}

pub fn duplicate_templates_placeholder_raises_test() {
  let tpl =
    "<!-- {{menu}} --><!-- {{templates}} --><!-- {{templates}} --><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateTemplates))
}
```

- [ ] **Step 2: Run tests to confirm RED**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

Expected: compile error — `layout.MissingBanner` / `DuplicateBanner` undefined; `layout.render` arity mismatch.

- [ ] **Step 3: Update `src/layout.gleam`**

Full replacement of the module:

```gleam
import gleam/list
import gleam/string

pub type LayoutError {
  MissingMenu
  MissingTemplates
  MissingBanner
  DuplicateMenu
  DuplicateTemplates
  DuplicateBanner
}

const menu_token = "<!-- {{menu}} -->"

const templates_token = "<!-- {{templates}} -->"

const banner_token = "<!-- {{banner}} -->"

pub fn validate(template: String) -> Result(Nil, LayoutError) {
  let menu_count = count_occurrences(template, menu_token)
  let tpls_count = count_occurrences(template, templates_token)
  let banner_count = count_occurrences(template, banner_token)
  case menu_count, tpls_count, banner_count {
    0, _, _ -> Error(MissingMenu)
    _, 0, _ -> Error(MissingTemplates)
    _, _, 0 -> Error(MissingBanner)
    n, _, _ if n > 1 -> Error(DuplicateMenu)
    _, n, _ if n > 1 -> Error(DuplicateTemplates)
    _, _, n if n > 1 -> Error(DuplicateBanner)
    _, _, _ -> Ok(Nil)
  }
}

pub fn render(
  template: String,
  menu_html: String,
  templates_html: String,
  banner_html: String,
) -> String {
  // Slugify in menu_render strips `<`, `>`, `{`, `}`, so the templates/banner
  // tokens cannot survive into menu_html — substitution order is safe.
  template
  |> string.replace(menu_token, menu_html)
  |> string.replace(templates_token, templates_html)
  |> string.replace(banner_token, banner_html)
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  list.length(parts) - 1
}
```

- [ ] **Step 4: Add the banner slot to `index.html`**

In `src/assets/index.html`, locate the `<nav class="menu">` block:

```html
<nav class="menu">
    <!-- {{menu}} -->
</nav>
```

Add the banner slot **directly after** the closing `</nav>` and before `<footer class="sidebar-foot">`:

```html
<nav class="menu">
    <!-- {{menu}} -->
</nav>

<!-- {{banner}} -->

<footer class="sidebar-foot">
```

- [ ] **Step 5: Add `.error-banner` CSS**

Append to `src/assets/static/styles.css`:

```css
.error-banner {
    margin: 12px 0 0;
    padding: 8px 12px;
    font-size: 0.85em;
    color: var(--ink-mute, #888);
    border-left: 2px solid var(--ink-mute, #888);
    background: transparent;
}
```

If `--ink-mute` is not defined in the existing stylesheet, the fallback `#888` keeps the banner readable.

- [ ] **Step 6: Update call sites to the new 4-arg `render`**

In `src/blogging.gleam`, the existing `layout.render(template, menu, tpls)` call becomes:

```gleam
let rendered_index = layout.render(template, menu, tpls, "")
```

In `test/end_to_end_test.gleam`:

```gleam
let rendered = layout.render(template, menu, tpls, "")
```

The end-to-end test's inline template string also needs the banner token. Change it to:

```gleam
let template =
  "<html><nav><!-- {{menu}} --></nav><banner><!-- {{banner}} --></banner><body><!-- {{templates}} --></body></html>"
```

- [ ] **Step 7: Regenerate the snapshot**

The snapshot at `test/snapshots/end_to_end.html` no longer matches because the template grew a `<banner></banner>` segment. Run:

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

The end-to-end test will fail and `echo` the actual rendered output. Copy that output verbatim into `test/snapshots/end_to_end.html`, replacing the file content. Re-run; the snapshot test should pass.

- [ ] **Step 8: Format check and commit**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format src test
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
git add src/layout.gleam src/assets/index.html src/assets/static/styles.css src/blogging.gleam test/layout_test.gleam test/end_to_end_test.gleam test/snapshots/end_to_end.html
git commit -m "feat(layout): add banner token (3rd placeholder)

layout.validate now requires <!-- {{banner}} --> exactly once; render takes
a banner string (empty = invisible). Snapshot regenerated. No network code."
```

---

## Task 3: Filename matcher (`parse_filename`)

**Spec mapping:** Phasing step 3, Section 2 (Discovery & parsing rules).

**Files:**
- Modify: `src/gist.gleam`
- Create: `test/gist_test.gleam`

**Done when:**
- Private `parse_filename` in `gist`. Module-private (not `pub`), but exposed via a `parse_filename_for_test` re-export so the test file can drive it.
- Unit tests cover every positive and negative case listed in Section 4 of the spec.
- `gleam test` green.

- [ ] **Step 1: Write the failing tests**

Create `test/gist_test.gleam`:

```gleam
import gist
import gleeunit/should

pub fn parse_filename_accepts_blog_prefix_test() {
  gist.parse_filename_for_test("blog:estudos:html.md")
  |> should.equal(Ok(#("estudos", "html")))
}

pub fn parse_filename_accepts_spaces_in_parts_test() {
  gist.parse_filename_for_test("blog:Estudos:HTML Intro.md")
  |> should.equal(Ok(#("Estudos", "HTML Intro")))
}

pub fn parse_filename_rejects_non_blog_prefix_test() {
  gist.parse_filename_for_test("README.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_empty_group_test() {
  gist.parse_filename_for_test("blog::foo.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_empty_leaf_test() {
  gist.parse_filename_for_test("blog:estudos:.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_no_md_suffix_test() {
  gist.parse_filename_for_test("blog:estudos:html")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_wrong_suffix_test() {
  gist.parse_filename_for_test("blog:estudos:html.txt")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_three_colons_test() {
  // 3+ colons is rejected by the "exactly 2 parts after the prefix" rule
  gist.parse_filename_for_test("blog:a:b:c.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_plain_text_test() {
  gist.parse_filename_for_test("notes.md")
  |> should.equal(Error(Nil))
}
```

- [ ] **Step 2: Run tests to confirm RED**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

Expected: compile error — `gist.parse_filename_for_test` does not exist.

- [ ] **Step 3: Implement `parse_filename`**

Append to `src/gist.gleam`:

```gleam
import gleam/list
import gleam/string

const blog_prefix = "blog:"

const md_suffix = ".md"

/// Test-only re-export. See `parse_filename`.
pub fn parse_filename_for_test(name: String) -> Result(#(String, String), Nil) {
  parse_filename(name)
}

/// Returns `Ok(#(group, leaf))` for filenames matching `blog:<group>:<leaf>.md`
/// with non-empty group and leaf, neither containing `:`. Rejects everything else.
fn parse_filename(name: String) -> Result(#(String, String), Nil) {
  use without_prefix <- with_prefix(name, blog_prefix)
  use without_suffix <- with_suffix(without_prefix, md_suffix)
  case string.split(without_suffix, ":") {
    [group, leaf] -> {
      case group, leaf {
        "", _ -> Error(Nil)
        _, "" -> Error(Nil)
        _, _ -> Ok(#(group, leaf))
      }
    }
    _ -> Error(Nil)
  }
}

fn with_prefix(
  s: String,
  prefix: String,
  k: fn(String) -> Result(a, Nil),
) -> Result(a, Nil) {
  case string.starts_with(s, prefix) {
    True -> k(string.drop_left(s, string.length(prefix)))
    False -> Error(Nil)
  }
}

fn with_suffix(
  s: String,
  suffix: String,
  k: fn(String) -> Result(a, Nil),
) -> Result(a, Nil) {
  case string.ends_with(s, suffix) {
    True -> k(string.drop_right(s, string.length(suffix)))
    False -> Error(Nil)
  }
}
```

Note: the `import gleam/list` line stays available for Task 4, even if unused here — remove it if format/lint complains, re-add in Task 4. (If `gleam format` strips it as unused, that is the desired behavior.)

- [ ] **Step 4: Run tests, format, commit**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format src test
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
git add src/gist.gleam test/gist_test.gleam
git commit -m "feat(gist): parse_filename for blog:<group>:<leaf>.md convention"
```

---

## Task 4: `fetch_all` + `HttpClient` capability with fake clients

**Spec mapping:** Phasing step 4, Section 3 (per-request flow), Section 4 (testing strategy).

**Files:**
- Modify: `src/gist.gleam`
- Modify: `test/gist_test.gleam`
- Create: `test/fixtures/gist_list.json`

**Done when:**
- `gist.fetch_all(client, user)` returns `Ok(List(Post))` sorted by `(slugify(group), slugify(leaf))`.
- Collision rule: same slugified `(group, leaf)` → first wins, log to stderr.
- Partial-failure rule: if one raw fetch returns `Error`, the failure is logged and the other posts succeed (we drop the failed one, we do **not** fail the whole request — except when the *list* call fails, which is a total failure).
- Total-failure rule: `list_gists` errors → return that `Error(GistError)` (whole-request banner).
- URL building tested in isolation.
- All assembly logic exercised by tests that inject fake `HttpClient` records — no real HTTP.
- `gleam test` green.

- [ ] **Step 1: Write the fixture**

Create `test/fixtures/gist_list.json` with a minimal canned response shape (one gist holding three files: two blog files in different groups, one non-blog file). Use the structure GitHub actually returns:

```json
[
  {
    "id": "abc123",
    "files": {
      "blog:estudos:html.md": { "filename": "blog:estudos:html.md" },
      "blog:estudos:css.md":  { "filename": "blog:estudos:css.md" },
      "notes.md":             { "filename": "notes.md" }
    }
  },
  {
    "id": "def456",
    "files": {
      "blog:ensaios:opening.md": { "filename": "blog:ensaios:opening.md" }
    }
  }
]
```

- [ ] **Step 2: Write the failing `fetch_all` tests**

Append to `test/gist_test.gleam`:

```gleam
import file_io
import gleam/list

fn ok_client(
  list_json: String,
  bodies: List(#(String, String)),
) -> gist.HttpClient {
  gist.HttpClient(
    list_gists: fn(_user) { Ok(list_json) },
    fetch_raw: fn(url) {
      case list.key_find(bodies, url) {
        Ok(body) -> Ok(body)
        Error(_) -> Error(gist.HttpError(404))
      }
    },
  )
}

pub fn fetch_all_returns_sorted_posts_test() {
  let assert Ok(list_json) = file_io.read_text("test/fixtures/gist_list.json")
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
      "# html\nbody",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:css.md",
      "# css\nbody",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/def456/raw/blog:ensaios:opening.md",
      "# opening\nbody",
    ),
  ]
  let assert Ok(posts) = gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  // Sorted by (slug(group), slug(leaf)). ensaios < estudos; within estudos: css < html.
  list.length(posts) |> should.equal(3)
  let assert Ok(p0) = list.first(posts)
  p0.group |> should.equal("ensaios")
  p0.leaf |> should.equal("opening")
  let assert Ok(p1) = list_at(posts, 1)
  p1.group |> should.equal("estudos")
  p1.leaf |> should.equal("css")
  let assert Ok(p2) = list_at(posts, 2)
  p2.group |> should.equal("estudos")
  p2.leaf |> should.equal("html")
}

pub fn fetch_all_filters_non_blog_files_test() {
  let assert Ok(list_json) = file_io.read_text("test/fixtures/gist_list.json")
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
      "x",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:css.md",
      "x",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/def456/raw/blog:ensaios:opening.md",
      "x",
    ),
  ]
  let assert Ok(posts) = gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  list.any(posts, fn(p) { p.leaf == "notes" }) |> should.be_false
}

pub fn fetch_all_total_failure_on_list_error_test() {
  let client =
    gist.HttpClient(
      list_gists: fn(_) { Error(gist.NetworkError("connection refused")) },
      fetch_raw: fn(_) { Ok("never called") },
    )
  gist.fetch_all(client, "Yuhigawa")
  |> should.equal(Error(gist.NetworkError("connection refused")))
}

pub fn fetch_all_partial_failure_drops_failed_post_test() {
  let assert Ok(list_json) = file_io.read_text("test/fixtures/gist_list.json")
  // Only two of three raw URLs respond OK. The third returns 404.
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
      "# html\nbody",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/def456/raw/blog:ensaios:opening.md",
      "# opening\nbody",
    ),
  ]
  let assert Ok(posts) = gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  list.length(posts) |> should.equal(2)
  list.any(posts, fn(p) { p.leaf == "css" }) |> should.be_false
}

pub fn fetch_all_collision_first_wins_test() {
  // Two gists, both define blog:dup:x.md. First in API order should win.
  let list_json =
    "[
      {\"id\": \"first\",  \"files\": {\"blog:dup:x.md\": {\"filename\": \"blog:dup:x.md\"}}},
      {\"id\": \"second\", \"files\": {\"blog:dup:x.md\": {\"filename\": \"blog:dup:x.md\"}}}
    ]"
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/first/raw/blog:dup:x.md",
      "WIN",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/second/raw/blog:dup:x.md",
      "LOSE",
    ),
  ]
  let assert Ok(posts) = gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  list.length(posts) |> should.equal(1)
  let assert Ok(p) = list.first(posts)
  p.body |> should.equal("WIN")
}

pub fn build_raw_url_test() {
  gist.build_raw_url_for_test("Yuhigawa", "abc123", "blog:estudos:html.md")
  |> should.equal(
    "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
  )
}

fn list_at(xs: List(a), i: Int) -> Result(a, Nil) {
  list.drop(xs, i) |> list.first
}
```

- [ ] **Step 3: Run tests to confirm RED**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

Expected: compile errors on `gist.fetch_all` (current stub returns `not implemented`) and `gist.build_raw_url_for_test` (does not exist).

- [ ] **Step 4: Implement assembly logic in `src/gist.gleam`**

Add slugify, URL building, JSON parsing, and the real `fetch_all`. Append to `src/gist.gleam`:

```gleam
import gleam/dynamic.{type Dynamic}
import gleam/io
import gleam/json
import gleam/result

/// Test-only re-export.
pub fn build_raw_url_for_test(
  user: String,
  gist_id: String,
  filename: String,
) -> String {
  build_raw_url(user, gist_id, filename)
}

fn build_raw_url(user: String, gist_id: String, filename: String) -> String {
  "https://gist.githubusercontent.com/"
  <> user
  <> "/"
  <> gist_id
  <> "/raw/"
  <> filename
}

/// Raw item from the gists list response — only the fields we use.
type GistEntry {
  GistEntry(id: String, filenames: List(String))
}

fn decode_gist_list(json_str: String) -> Result(List(GistEntry), GistError) {
  let entry_decoder =
    dynamic.decode2(
      GistEntry,
      dynamic.field("id", dynamic.string),
      dynamic.field(
        "files",
        fn(d: Dynamic) -> Result(List(String), List(dynamic.DecodeError)) {
          // GitHub returns "files" as an object keyed by filename. We only need the keys.
          // gleam_dynamic exposes `dict` decoding via `dynamic.dict`.
          dynamic.dict(dynamic.string, dynamic.dynamic)(d)
          |> result.map(fn(map) { dict_keys(map) })
        },
      ),
    )
  json.decode(from: json_str, using: dynamic.list(entry_decoder))
  |> result.map_error(fn(_err) { ParseError("decode error") })
}

@external(erlang, "maps", "keys")
fn dict_keys(d: anything) -> List(String)

/// Live entrypoint. Production code passes the live HttpClient (Task 5).
pub fn fetch_all(
  client: HttpClient,
  user: String,
) -> Result(List(Post), GistError) {
  use list_json <- result.try(client.list_gists(user))
  use entries <- result.try(decode_gist_list(list_json))
  let candidates = collect_candidates(entries, user)
  let posts = fetch_bodies(client, candidates)
  Ok(dedupe(sort_by_slug(posts)))
}

/// (group, leaf, raw_url) tuples for every file that matches the convention.
fn collect_candidates(
  entries: List(GistEntry),
  user: String,
) -> List(#(String, String, String)) {
  list.flat_map(entries, fn(e) {
    list.filter_map(e.filenames, fn(filename) {
      case parse_filename(filename) {
        Error(_) -> Error(Nil)
        Ok(#(g, l)) -> Ok(#(g, l, build_raw_url(user, e.id, filename)))
      }
    })
  })
}

fn fetch_bodies(
  client: HttpClient,
  candidates: List(#(String, String, String)),
) -> List(Post) {
  list.filter_map(candidates, fn(c) {
    let #(g, l, url) = c
    case client.fetch_raw(url) {
      Ok(body) -> Ok(Post(group: g, leaf: l, body: body))
      Error(err) -> {
        log_warn("fetch_raw failed for " <> url <> ": " <> error_label(err))
        Error(Nil)
      }
    }
  })
}

fn sort_by_slug(posts: List(Post)) -> List(Post) {
  list.sort(posts, by: fn(a, b) {
    let ka = slug(a.group) <> "/" <> slug(a.leaf)
    let kb = slug(b.group) <> "/" <> slug(b.leaf)
    string.compare(ka, kb)
  })
}

fn dedupe(posts: List(Post)) -> List(Post) {
  // First wins. Walks left-to-right; tracks seen `slug(group)/slug(leaf)` keys.
  let #(kept, _seen) =
    list.fold(posts, #([], []), fn(acc, p) {
      let #(kept, seen) = acc
      let key = slug(p.group) <> "/" <> slug(p.leaf)
      case list.contains(seen, key) {
        True -> {
          log_warn("collision dropped: " <> key)
          #(kept, seen)
        }
        False -> #([p, ..kept], [key, ..seen])
      }
    })
  list.reverse(kept)
}

fn slug(s: String) -> String {
  s
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.to_graphemes
  |> list.filter(fn(c) { is_alnum(c) || c == "-" || c == "_" })
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

fn log_warn(msg: String) -> Nil {
  io.println_error("[gist] " <> msg)
}

fn error_label(err: GistError) -> String {
  case err {
    NetworkError(reason) -> "NetworkError(" <> reason <> ")"
    HttpError(status) -> "HttpError(" <> int_to_string(status) <> ")"
    ParseError(reason) -> "ParseError(" <> reason <> ")"
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String
```

Also delete the placeholder `fetch_all` body from Task 1 and replace it with the real one above (or simply allow the new body to overwrite the stub during this edit).

**Note on `gleam_json` decoder shape:** the snippet uses `dynamic.dict` and `gleam/json.decode`. The exact decoder API may differ between minor versions of `gleam_json` and `gleam_dynamic`. If it does, the implementer should consult `gleam/json` docs (e.g. `json.parse` vs `json.decode`) and adapt — the *behavior* required (parse JSON array → list of `{id, files}` → list of filenames) is fixed; the call signatures are not.

- [ ] **Step 5: Run tests, format, commit**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format src test
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
git add src/gist.gleam test/gist_test.gleam test/fixtures/gist_list.json
git commit -m "feat(gist): fetch_all with HttpClient capability, sort, dedupe, partial-failure tolerance

Assembly logic only — no live HTTP yet. Tests inject fake clients. Collisions
log to stderr; partial raw-fetch failures drop the offending post without
failing the whole request. Total list-call failure surfaces to caller."
```

---

## Task 5: Live HTTP client + gated live test

**Spec mapping:** Phasing step 5, Dependencies section, Section 4 (gated live test).

**Files:**
- Modify: `src/gist.gleam`
- Modify: `test/gist_test.gleam`

**Done when:**
- `gist.live_client()` returns an `HttpClient` whose `list_gists` and `fetch_raw` use `gleam_httpc` against `https://api.github.com/users/<user>/gists?per_page=100` and the raw CDN URL, respectively, with a 5 s per-call timeout.
- Non-2xx responses become `HttpError(status)`; transport errors become `NetworkError(reason)`.
- Gated live test runs only when `BLOG_LIVE_TEST=1`, hits the real `Yuhigawa` user, asserts at least one post is returned (skip with `True |> should.be_true` if env unset).
- `gleam test` green; live test skipped by default.

- [ ] **Step 1: Write the gated live test**

Append to `test/gist_test.gleam`:

```gleam
import gleam/erlang/os
import gleam/list

pub fn live_fetch_yuhigawa_test() {
  case os.get_env("BLOG_LIVE_TEST") {
    Ok("1") -> {
      let client = gist.live_client()
      case gist.fetch_all(client, "Yuhigawa") {
        Ok(posts) -> {
          // The user may have zero matching gists at the moment. We only assert
          // that the call returned Ok — the contract is "the live wiring works",
          // not "Yuhigawa has at least one post right now".
          should.be_true(list.length(posts) >= 0)
        }
        Error(err) -> {
          // Surface the failure with a useful message.
          should.equal(err, gist.NetworkError("live test expected Ok"))
        }
      }
    }
    _ -> should.be_true(True)
  }
}
```

- [ ] **Step 2: Run tests to confirm RED**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

Expected: compile error — `gist.live_client` undefined.

- [ ] **Step 3: Implement `live_client`**

Append to `src/gist.gleam`:

```gleam
import gleam/http/request as http_req
import gleam/http/response as http_resp
import gleam/httpc

pub fn live_client() -> HttpClient {
  HttpClient(
    list_gists: live_list_gists,
    fetch_raw: live_fetch_raw,
  )
}

fn live_list_gists(user: String) -> Result(String, GistError) {
  let assert Ok(req) =
    http_req.to(
      "https://api.github.com/users/" <> user <> "/gists?per_page=100",
    )
  let req =
    req
    |> http_req.prepend_header("accept", "application/vnd.github+json")
    |> http_req.prepend_header("user-agent", "yuhigawa-blog-engine")
  send_with_timeout(req)
}

fn live_fetch_raw(url: String) -> Result(String, GistError) {
  let assert Ok(req) = http_req.to(url)
  let req =
    req
    |> http_req.prepend_header("user-agent", "yuhigawa-blog-engine")
  send_with_timeout(req)
}

fn send_with_timeout(req: http_req.Request(String)) -> Result(String, GistError) {
  // 5 s per call. gleam_httpc surfaces its own error type; map to GistError.
  case httpc.send(req) {
    Ok(resp) -> {
      case resp.status {
        s if s >= 200 && s < 300 -> Ok(resp.body)
        s -> Error(HttpError(s))
      }
    }
    Error(reason) -> Error(NetworkError(string_inspect(reason)))
  }
}
```

**Note on the timeout:** `gleam_httpc` may not expose a per-call timeout knob directly (it may delegate to `hackney` defaults). If a timeout-configuration API is missing, the implementer should use the timeout knob the library *does* expose; if none exists, document the gap in the spec's Hardening Log and rely on the whole-handler 15 s cap added in Task 6.

**Note on the `gleam_httpc` API shape:** the exact module name (`gleam/httpc` vs `gleam/http/httpc`), the function (`send` vs `request`), and the request-builder (`http_req.to` vs `request.new`) may have changed between versions. The implementer should consult the installed `gleam_httpc` docs (`docker compose run --rm blogging gleam docs build` or browse the source under `build/packages/gleam_httpc/src/`) and adapt the imports. The *behavior* is fixed; the call signatures are not.

- [ ] **Step 4: Run the gated test by hand once, with and without env**

```bash
# Without env — should pass (test skipped).
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test

# With env — should hit GitHub.
BLOG_LIVE_TEST=1 docker compose run --rm --no-deps -e BLOG_LIVE_TEST=1 -v "$(pwd):/app" blogging gleam test
```

The live invocation only needs to run **once locally** to confirm wiring. CI does not need to run it.

- [ ] **Step 5: Format and commit**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format src test
git add src/gist.gleam test/gist_test.gleam
git commit -m "feat(gist): live HTTP client via gleam_httpc + gated live test"
```

---

## Task 6: Wire `gist.fetch_all` into `blogging.gleam` with 15 s handler cap

**Spec mapping:** Phasing step 6, Section 3 (Boot / Per-request flow / Observability).

**Files:**
- Modify: `src/blogging.gleam`
- Modify: `docker-compose.yml`

**Done when:**
- Boot reads `BLOG_GIST_USER` env var; missing/empty → `panic` with `"set BLOG_GIST_USER=<github-username>"`.
- Boot validates the template (existing) — no scan, no network.
- Handler `/` does `gist.fetch_all(live_client, user)` on every request.
- On `Ok(posts)`: render with `menu_render.build` + `layout.render(template, menu, tpls, "")`.
- On `Error(err)`: log to stderr, render with `layout.render(template, "", "", banner_html)`, status **200**.
- 15 s whole-handler timeout cap — fetch wrapped so the request can't exceed 15 s; on timeout, falls back to the banner path.
- `scanner.gleam` is no longer called from `blogging.gleam` (but the module is **not yet deleted** — that's Task 7).
- `docker compose up blogging` boots and `curl localhost:3000/` returns 200.
- `docker compose run` with `BLOG_GIST_USER` unset crashes with the documented message.
- `gleam test` green.

- [ ] **Step 1: Update `docker-compose.yml`**

```yaml
services:
  blogging:
    build: .
    ports:
      - "3000:3000"
    restart: unless-stopped
    environment:
      BLOG_GIST_USER: Yuhigawa
```

- [ ] **Step 2: Update `src/blogging.gleam`**

Full replacement:

```gleam
import file_io
import gist
import gleam/bytes_builder.{type BytesBuilder}
import gleam/erlang/os
import gleam/erlang/process
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/result
import gleam/string
import layout
import menu_render
import static_serve

const handler_timeout_ms = 15_000

const banner_html = "<div class=\"error-banner\" role=\"status\">Couldn't reach GitHub right now — the menu will come back when GitHub does.</div>"

pub fn main() {
  let user = case os.get_env("BLOG_GIST_USER") {
    Ok(v) ->
      case string.trim(v) {
        "" -> panic as "set BLOG_GIST_USER=<github-username>"
        s -> s
      }
    Error(_) -> panic as "set BLOG_GIST_USER=<github-username>"
  }
  let assert Ok(template) = file_io.read_text("src/assets/index.html")
  let assert Ok(_) = layout.validate(template)
  let client = gist.live_client()
  elli.become(fn(req) { handler(template, client, user, req) }, on_port: 3000)
}

fn handler(
  template: String,
  client: gist.HttpClient,
  user: String,
  req: Request(t),
) -> Response(BytesBuilder) {
  case req.path {
    "/" -> serve_index(template, client, user)
    path ->
      case string.starts_with(path, "/static/") {
        True -> static_serve.serve(string.drop_left(path, 8))
        False -> not_found()
      }
  }
}

fn serve_index(
  template: String,
  client: gist.HttpClient,
  user: String,
) -> Response(BytesBuilder) {
  let rendered = case fetch_with_cap(client, user) {
    Ok(posts) -> render_ok(template, posts)
    Error(err) -> {
      log_error(err, user)
      render_error(template)
    }
  }
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(bytes_builder.from_string(rendered))
}

fn fetch_with_cap(
  client: gist.HttpClient,
  user: String,
) -> Result(List(gist.Post), gist.GistError) {
  // Run fetch_all in a child process; wait at most handler_timeout_ms.
  // Subject must be created before the child is spawned so the child can send to it.
  let subject = process.new_subject()
  let _pid =
    process.start(
      linked: False,
      running: fn() {
        let result = gist.fetch_all(client, user)
        process.send(subject, result)
      },
    )
  case process.receive(subject, handler_timeout_ms) {
    Ok(result) -> result
    Error(Nil) -> Error(gist.NetworkError("handler timeout"))
  }
}

fn render_ok(template: String, posts: List(gist.Post)) -> String {
  let #(menu, tpls) = menu_render.build(posts)
  layout.render(template, menu, tpls, "")
}

fn render_error(template: String) -> String {
  layout.render(template, "", "", banner_html)
}

fn log_error(err: gist.GistError, user: String) -> Nil {
  let label = case err {
    gist.NetworkError(reason) -> "NetworkError(" <> reason <> ")"
    gist.HttpError(status) -> "HttpError(" <> int_to_string(status) <> ")"
    gist.ParseError(reason) -> "ParseError(" <> reason <> ")"
  }
  io.println_error("[gist] " <> label <> " for user=" <> user)
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String

fn not_found() -> Response(BytesBuilder) {
  response.new(404)
  |> response.prepend_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(bytes_builder.from_string("not found"))
}
```

Note: `result` import may end up unused after edits — let `gleam format` strip it. Same for `string` (used for `trim` and `starts_with`/`drop_left`).

**Note on the timeout primitive:** `process.start` + `process.new_subject` + `process.receive(_, timeout_ms)` is the canonical Gleam pattern for "do something with a timeout". The exact API may have changed between `gleam_erlang` versions. If `process.new_subject` requires a different setup, consult `build/packages/gleam_erlang/src/gleam/erlang/process.gleam` — the *behavior* required is "if `fetch_all` hasn't returned in 15 s, give up and render the banner."

- [ ] **Step 3: Run tests**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

Expected: all tests pass. None of them exercise the live path — they exercise `gist.fetch_all` with fake clients, which works unchanged.

- [ ] **Step 4: Smoke-test the boot**

```bash
# Should crash with the documented message.
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam run 2>&1 | head -5

# Should boot and serve.
docker compose up -d blogging
sleep 3
curl -i http://localhost:3000/ | head -10
docker compose logs blogging | tail -20
docker compose down
```

Expected on the first call: panic with "set BLOG_GIST_USER=<github-username>".
Expected on the second call: 200 with HTML containing the sidebar and (if Yuhigawa has matching gists) `<li class="submenu-item"` entries.

If the live fetch fails for any reason (rate limit, transient), the response should still be 200 with the `error-banner` div visible in the HTML and a `[gist] ...` line in the docker logs.

- [ ] **Step 5: Format and commit**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format src test
git add src/blogging.gleam docker-compose.yml
git commit -m "feat(blogging): per-request gist fetch with 15s cap and banner-on-error

Boot reads BLOG_GIST_USER (panics if unset). Handler fetches every request,
logs every GistError to stderr, renders the banner on any failure (status 200).
Scanner is no longer called from main — deletion follows in the next commit."
```

---

## Task 7: Delete scanner + posts directories + update README

**Spec mapping:** Phasing step 7.

**Files:**
- Delete: `src/scanner.gleam`
- Delete: `test/scanner_test.gleam`
- Delete: `test/fixtures/posts/` (entire subtree)
- Delete: `src/assets/posts/` (entire subtree)
- Modify: `test/end_to_end_test.gleam` (switch fixture from `scanner.scan` to inline `[gist.Post(...)]`)
- Modify: `test/snapshots/end_to_end.html` (regenerate against the new fixture)
- Modify: `src/blogging.gleam` (remove `import scanner` if still present)
- Modify: `README.md`

**Done when:**
- `find src test -name '*scanner*' -o -path '*/posts/*'` returns empty (only check inside src and test).
- `grep -r 'scanner' src/` returns empty.
- `gleam test` green; `gleam format --check src test` green.
- `docker compose up blogging` still boots and serves.

- [ ] **Step 1: Rewrite `test/end_to_end_test.gleam` to use inline `gist.Post` fixtures**

Full replacement:

```gleam
import file_io
import gist
import gleeunit/should
import layout
import menu_render

pub fn end_to_end_snapshot_test() {
  let template =
    "<html><nav><!-- {{menu}} --></nav><banner><!-- {{banner}} --></banner><body><!-- {{templates}} --></body></html>"
  let posts = [
    gist.Post(group: "estudos", leaf: "css", body: "# css\nbody"),
    gist.Post(group: "estudos", leaf: "html", body: "# html\nbody"),
    gist.Post(
      group: "estudos",
      leaf: "notes.mdx",
      body: "# notes.mdx\nbody",
    ),
    gist.Post(group: "skipme", leaf: "keep", body: "# keep\nbody"),
  ]
  let #(menu, tpls) = menu_render.build(posts)
  let rendered = layout.render(template, menu, tpls, "")
  let assert Ok(expected) = file_io.read_text("test/snapshots/end_to_end.html")
  case rendered == expected {
    True -> should.be_true(True)
    False -> {
      echo rendered
      should.equal(rendered, expected)
    }
  }
}
```

- [ ] **Step 2: Delete scanner and posts**

```bash
rm src/scanner.gleam
rm test/scanner_test.gleam
rm -rf test/fixtures/posts
rm -rf src/assets/posts
```

- [ ] **Step 3: Remove `import scanner` from `blogging.gleam` if any remains**

```bash
grep -n 'scanner' src/blogging.gleam || echo "clean"
```

If the file still imports or references `scanner`, remove the import line and any leftover references.

- [ ] **Step 4: Regenerate the snapshot**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
```

The end-to-end test fails and echoes the new rendered HTML. Copy the echoed output into `test/snapshots/end_to_end.html`, replacing the entire file. Re-run; the snapshot test passes.

- [ ] **Step 5: Verify the cleanup is complete**

```bash
find src test -name '*scanner*' -o -path '*/posts/*' 2>/dev/null
# expected: empty
grep -r 'scanner' src/
# expected: empty
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format --check src test
```

- [ ] **Step 6: Update `README.md`**

Replace the **How it works** section (currently describing filesystem scan) with:

```markdown
## How it works

Posts live in the configured user's public GitHub gists. Any file inside any of
those gists whose name matches `blog:<group>:<leaf>.md` becomes a sidebar entry
under `<group>` with label `<leaf>` and content rendered from the file body.
Files not matching the pattern are silently ignored.

The server reads `BLOG_GIST_USER` at boot. On every request to `/`, it fetches
`GET https://api.github.com/users/<user>/gists` (1 call, anonymous quota of
60/hr per server IP), then fetches each matching file body via
`gist.githubusercontent.com/<user>/<id>/raw/<filename>` (no quota). The page
always reflects the live state of the gists.

If GitHub is unreachable, the page still loads with an empty menu and a small
banner in the sidebar; the status code stays 200.

## Add a post

Create a file in any of your public gists named `blog:<group>:<leaf>.md`.
That's it. One gist can hold multiple `blog:*` files.

## Configure

Set `BLOG_GIST_USER` to your GitHub username in `docker-compose.yml`:

```yaml
environment:
  BLOG_GIST_USER: <your-github-username>
```
```

The **Markdown subset**, **Static files**, **Run**, and **Test** sections stay as-is.

Update the **Status** section:

```markdown
## Status

Gist phase. Caching, per-post URLs, syntax highlighting, and authenticated
fetch (private gists, raised rate limit) are deferred.
```

- [ ] **Step 7: Final test, format, commit**

```bash
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format --check src test
git add -A
git status  # double-check that scanner.gleam, scanner_test.gleam, test/fixtures/posts/, src/assets/posts/ are all in the "deleted" list
git commit -m "refactor: delete scanner module and local posts source

Gist is now the only source. Removed src/scanner.gleam, test/scanner_test.gleam,
test/fixtures/posts/, src/assets/posts/. end_to_end_test uses inline gist.Post
fixtures. README updated."
```

- [ ] **Step 8: Final smoke test of the running server**

```bash
docker compose up -d blogging
sleep 3
curl -i http://localhost:3000/ | head -20
docker compose logs blogging | tail -10
docker compose down
```

Expected: 200 response, sidebar reflects Yuhigawa's gists, no errors in the log (assuming the live fetch succeeds; if rate-limited, expect the banner div in HTML and a `[gist] ...` line in the log — both are acceptable end-states).

---

## After all tasks: final review

Dispatch the final reviewer subagent over the entire diff of `feat/gist-integration` vs `master`. Append any consolidated lessons to the spec's Hardening Log. Report the branch status (commit count, test count, success-criteria walkthrough).
