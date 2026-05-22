import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import render

pub fn server_handler(req: Request(t)) -> Response(BytesBuilder) {
  case req.path {
    "/styles.css" -> serve_css()
    _ -> serve_index()
  }
}

fn serve_index() -> Response(BytesBuilder) {
  let html_content = render.file_to_string("index.html")
  let concatenated_content =
    render.concatenate_templates(html_content, ["html.md", "css.md"])
  let body = bytes_builder.from_string(concatenated_content)

  response.new(200)
  |> response.prepend_header("made-with", "Gleam")
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(body)
}

fn serve_css() -> Response(BytesBuilder) {
  let css = render.file_to_string("styles.css")
  let body = bytes_builder.from_string(css)

  response.new(200)
  |> response.prepend_header("content-type", "text/css; charset=utf-8")
  |> response.set_body(body)
}

pub fn main() {
  elli.become(server_handler, on_port: 3000)
}
