import file_io
import gist
import gleam/bytes_builder.{type BytesBuilder}
import gleam/erlang/os
import gleam/erlang/process
import gleam/http/elli
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/string
import layout
import menu_render
import static_serve

const handler_timeout_ms = 15_000

const banner_html = "<div class=\"error-banner\" role=\"status\">Couldn't reach GitHub right now — the menu will come back when GitHub does.</div>"

pub fn main() {
  let user = case os.get_env("BLOG_GIST_USER") {
    Ok(v) ->
      case string.trim(v) {
        "" -> panic as "set BLOG_GIST_USER=<github-username>"
        s -> s
      }
    Error(_) -> panic as "set BLOG_GIST_USER=<github-username>"
  }
  let assert Ok(template) = file_io.read_text("src/assets/index.html")
  let assert Ok(_) = layout.validate(template)
  let client = gist.live_client()
  elli.become(fn(req) { handler(template, client, user, req) }, on_port: 3000)
}

fn handler(
  template: String,
  client: gist.HttpClient,
  user: String,
  req: Request(t),
) -> Response(BytesBuilder) {
  case req.path {
    "/" -> serve_index(template, client, user)
    path ->
      case string.starts_with(path, "/static/") {
        True -> static_serve.serve(string.drop_left(path, 8))
        False -> not_found()
      }
  }
}

fn serve_index(
  template: String,
  client: gist.HttpClient,
  user: String,
) -> Response(BytesBuilder) {
  let rendered = case fetch_with_cap(client, user) {
    Ok(posts) -> render_ok(template, posts)
    Error(err) -> {
      log_error(err, user)
      render_error(template)
    }
  }
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(bytes_builder.from_string(rendered))
}

fn fetch_with_cap(
  client: gist.HttpClient,
  user: String,
) -> Result(List(gist.Post), gist.GistError) {
  // Run fetch_all in a child process; wait at most handler_timeout_ms.
  // Subject must be created before the child is spawned so the child can send to it.
  let subject = process.new_subject()
  let _pid =
    process.start(linked: False, running: fn() {
      let result = gist.fetch_all(client, user)
      process.send(subject, result)
    })
  case process.receive(subject, handler_timeout_ms) {
    Ok(result) -> result
    Error(Nil) -> Error(gist.NetworkError("handler timeout"))
  }
}

fn render_ok(template: String, posts: List(gist.Post)) -> String {
  let #(menu, tpls) = menu_render.build(posts)
  layout.render(template, menu, tpls, "")
}

fn render_error(template: String) -> String {
  layout.render(template, "", "", banner_html)
}

fn log_error(err: gist.GistError, user: String) -> Nil {
  let label = case err {
    gist.NetworkError(reason) -> "NetworkError(" <> reason <> ")"
    gist.HttpError(status) -> "HttpError(" <> int.to_string(status) <> ")"
    gist.ParseError(reason) -> "ParseError(" <> reason <> ")"
  }
  io.println_error("[gist] " <> label <> " for user=" <> user)
}

fn not_found() -> Response(BytesBuilder) {
  response.new(404)
  |> response.prepend_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(bytes_builder.from_string("not found"))
}
