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

fn list_length(xs: List(a)) -> Int {
  list.length(xs)
}

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

fn first(xs: List(a)) -> Result(a, Nil) {
  list.first(xs)
}

fn string_contains(s: String, sub: String) -> Bool {
  string.contains(s, sub)
}
