import file_io
import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/string
import layout
import menu_render
import scanner
import static_serve

pub fn main() {
  let assert Ok(template) = file_io.read_text("src/assets/index.html")
  let assert Ok(_) = layout.validate(template)
  let assert Ok(scan) = scanner.scan("src/assets/posts")
  let #(menu, tpls) = menu_render.build(scan)
  let rendered_index = layout.render(template, menu, tpls)
  elli.become(fn(req) { handler(rendered_index, req) }, on_port: 3000)
}

fn handler(rendered_index: String, req: Request(t)) -> Response(BytesBuilder) {
  case string.starts_with(req.path, "/static/") {
    True -> static_serve.serve(string.drop_left(req.path, 8))
    False -> serve_index(rendered_index)
  }
}

fn serve_index(rendered_index: String) -> Response(BytesBuilder) {
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(bytes_builder.from_string(rendered_index))
}
