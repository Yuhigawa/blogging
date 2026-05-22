import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/string
import render
import static_serve

pub fn server_handler(req: Request(t)) -> Response(BytesBuilder) {
  case req.path {
    "/" -> serve_index()
    _ ->
      case string.starts_with(req.path, "/static/") {
        True -> static_serve.serve(string.drop_left(req.path, 8))
        False -> not_found()
      }
  }
}

fn serve_index() -> Response(BytesBuilder) {
  let html_content = render.file_to_string("index.html")
  let concatenated_content =
    render.concatenate_templates(html_content, [
      "posts/estudos/html.md",
      "posts/estudos/css.md",
    ])
  let body = bytes_builder.from_string(concatenated_content)

  response.new(200)
  |> response.prepend_header("made-with", "Gleam")
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(body)
}

fn not_found() -> Response(BytesBuilder) {
  response.new(404)
  |> response.prepend_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(bytes_builder.from_string("not found"))
}

pub fn main() {
  elli.become(server_handler, on_port: 3000)
}
