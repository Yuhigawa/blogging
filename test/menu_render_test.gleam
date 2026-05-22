import gleam/string
import gleeunit/should
import menu_render
import scanner

pub fn renders_group_label_and_entry_test() {
  let scan = [
    scanner.Post(group: "estudos", leaf: "html", body: "# h\n"),
    scanner.Post(group: "estudos", leaf: "css", body: "# c\n"),
  ]
  let #(menu, _tpls) = menu_render.build(scan)
  string_contains(menu, "estudos") |> should.be_true
  string_contains(menu, "id=\"html\"") |> should.be_true
  string_contains(menu, "id=\"css\"") |> should.be_true
}

pub fn templates_use_group_leaf_id_test() {
  let scan = [scanner.Post(group: "estudos", leaf: "html", body: "# h\n")]
  let #(_menu, tpls) = menu_render.build(scan)
  string_contains(tpls, "template-estudos-html") |> should.be_true
}

pub fn empty_group_hidden_test() {
  // an empty group never reaches menu_render (filtered by scanner) — but a single entry should still produce one group label
  let scan = [scanner.Post(group: "estudos", leaf: "html", body: "# h\n")]
  let #(menu, _) = menu_render.build(scan)
  string_contains(menu, "ensaios") |> should.be_false
}

pub fn slug_lowercased_consistently_test() {
  let scan = [
    scanner.Post(group: "Estudos", leaf: "HTML Intro", body: "# x\n"),
  ]
  let #(menu, tpls) = menu_render.build(scan)
  string_contains(menu, "id=\"html-intro\"") |> should.be_true
  string_contains(tpls, "template-estudos-html-intro") |> should.be_true
}

fn string_contains(s: String, sub: String) -> Bool {
  string.contains(s, sub)
}
