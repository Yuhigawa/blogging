import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import render

pub fn server_handler(_request: Request(t)) -> Response(BytesBuilder) {
  // let html_content = render.convert_markdown_to_html("main.md")
  let html_content = render.file_to_string("index.html")
  let concatenated_content =
    render.concatenate_templates(html_content, ["submenu1.md", "submenu2.md"])
  let body = bytes_builder.from_string(concatenated_content)

  response.new(200)
  |> response.prepend_header("made-with", "Gleam")
  |> response.set_body(body)
}

pub fn main() {
  elli.become(server_handler, on_port: 3000)
}
