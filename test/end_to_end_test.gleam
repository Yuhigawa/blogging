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
    gist.Post(group: "estudos", leaf: "notes.mdx", body: "# notes.mdx\nbody"),
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
