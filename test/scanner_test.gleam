import gleam/list
import gleam/string
import gleeunit/should
import scanner

pub fn scan_returns_groups_and_leaves_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // estudos: css.md, html.md, notes.mdx.md → 3
  // skipme:  keep.md (README.md + .hidden filtered) → 1
  // ensaios: empty → 0
  list.length(entries) |> should.equal(4)
}

pub fn scan_is_sorted_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // Sorted by (group, leaf): estudos/css before estudos/html before estudos/notes.mdx.
  pair_of(entries, 0) |> should.equal(#("estudos", "css"))
  pair_of(entries, 1) |> should.equal(#("estudos", "html"))
  pair_of(entries, 2) |> should.equal(#("estudos", "notes.mdx"))
  pair_of(entries, 3) |> should.equal(#("skipme", "keep"))
}

pub fn scan_strips_only_md_suffix_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // Regression: ensure ".md" substring isn't stripped from inside the filename.
  // notes.mdx.md → leaf "notes.mdx", NOT "notes.x".
  list.any(entries, fn(p) { p.group == "estudos" && p.leaf == "notes.mdx" })
  |> should.be_true
  list.any(entries, fn(p) { p.leaf == "notes.x" }) |> should.be_false
}

pub fn scan_excludes_empty_group_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // ensaios/ has no .md files → no entries from that group.
  list.any(entries, fn(p) { p.group == "ensaios" }) |> should.be_false
}

pub fn scan_skips_readme_named_files_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // skipme/ contains README.md alongside keep.md. Group survives via keep.md;
  // README.md must not appear.
  list.any(entries, fn(p) { p.leaf == "README" }) |> should.be_false
}

pub fn scan_skips_hidden_files_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  // skipme/.hidden must not appear. Group survives via keep.md.
  list.any(entries, fn(p) { p.leaf == ".hidden" || p.leaf == "" })
  |> should.be_false
}

pub fn scan_returns_body_test() {
  let assert Ok(entries) = scanner.scan("test/fixtures/posts")
  let assert Ok(post) = list.first(entries)
  string.contains(post.body, "body") |> should.be_true
}

fn pair_of(xs: List(scanner.Post), i: Int) -> #(String, String) {
  let assert Ok(scanner.Post(group: g, leaf: l, ..)) = list_at(xs, i)
  #(g, l)
}

fn list_at(xs: List(a), i: Int) -> Result(a, Nil) {
  list.drop(xs, i) |> list.first
}
