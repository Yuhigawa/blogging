import file_io
import gleeunit/should
import layout
import menu_render
import scanner

pub fn end_to_end_snapshot_test() {
  let template =
    "<html><nav><!-- {{menu}} --></nav><body><!-- {{templates}} --></body></html>"
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
