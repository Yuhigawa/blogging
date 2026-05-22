import gleam/list
import gleam/string
import md
import scanner

pub fn build(scan: List(scanner.Post)) -> #(String, String) {
  let groups = group_by_first(scan)
  let menu =
    groups
    |> list.map(render_group)
    |> string.join("\n")

  let tpls =
    scan
    |> list.map(fn(p) {
      let gid = slugify(p.group)
      let lid = slugify(p.leaf)
      "<template id=\"template-"
      <> gid
      <> "-"
      <> lid
      <> "\">"
      <> render_post_body(p.body)
      <> "</template>"
    })
    |> string.join("\n")

  #(menu, tpls)
}

fn render_group(g: #(String, List(scanner.Post))) -> String {
  let #(group, entries) = g
  let gid = slugify(group)
  let items =
    entries
    |> list.map(fn(p) {
      let lid = slugify(p.leaf)
      "<li class=\"submenu-item\" id=\""
      <> lid
      <> "\" data-group=\""
      <> gid
      <> "\">"
      <> p.leaf
      <> "</li>"
    })
    |> string.join("\n")
  "<div class=\"menu-group\">\n"
  <> "<div class=\"group-label\">"
  <> group
  <> "</div>\n"
  <> "<ul>"
  <> items
  <> "</ul>\n"
  <> "</div>"
}

fn group_by_first(
  scan: List(scanner.Post),
) -> List(#(String, List(scanner.Post))) {
  // Preserve sort order; group consecutive same-group entries.
  list.fold(scan, [], fn(acc, p) {
    case acc {
      [#(prev_g, items), ..rest] if prev_g == p.group -> [
        #(prev_g, list.append(items, [p])),
        ..rest
      ]
      _ -> [#(p.group, [p]), ..acc]
    }
  })
  |> list.reverse
}

fn render_post_body(body: String) -> String {
  md.to_html(body)
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
  |> list.filter(fn(c) { is_alnum(c) || c == "-" || c == "_" })
  |> string.concat
}

fn is_alnum(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9" -> True
    _ -> False
  }
}
