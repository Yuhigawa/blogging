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
