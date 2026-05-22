import gist
import gleam/list
import gleam/string
import md
import slug

pub fn build(scan: List(gist.Post)) -> #(String, String) {
  let groups = group_by_first(scan)
  let menu =
    groups
    |> list.map(render_group)
    |> string.join("\n")

  let tpls =
    scan
    |> list.map(fn(p) {
      let gid = slug.slugify(p.group)
      let lid = slug.slugify(p.leaf)
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

fn render_group(g: #(String, List(gist.Post))) -> String {
  let #(group, entries) = g
  let gid = slug.slugify(group)
  let items =
    entries
    |> list.map(fn(p) {
      let lid = slug.slugify(p.leaf)
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

fn group_by_first(scan: List(gist.Post)) -> List(#(String, List(gist.Post))) {
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
