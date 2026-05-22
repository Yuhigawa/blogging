import file_io
import gleam/bytes_builder.{type BytesBuilder}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub fn serve(path: String) -> Response(BytesBuilder) {
  case resolve(path) {
    None -> not_found()
    Some(full) ->
      case file_io.read_text(full) {
        Ok(body) ->
          response.new(200)
          |> response.prepend_header("content-type", mime_for(path))
          |> response.prepend_header("cache-control", "no-cache, must-revalidate")
          |> response.set_body(bytes_builder.from_string(body))
        Error(_) -> not_found()
      }
  }
}

pub fn resolve(path: String) -> Option(String) {
  // elli does not URL-decode req.path; encoded variants like %2e%2e arrive literal
  // and are rejected by the substring guard. Any decoding middleware added upstream
  // must re-validate before reaching this point.
  case string.starts_with(path, "/") || string.contains(path, "..") {
    True -> None
    False -> Some("src/assets/static/" <> path)
  }
}

pub fn mime_for(path: String) -> String {
  case extension(path) {
    "css" -> "text/css; charset=utf-8"
    "js" -> "text/javascript; charset=utf-8"
    "svg" -> "image/svg+xml"
    "png" -> "image/png"
    "jpg" -> "image/jpeg"
    "jpeg" -> "image/jpeg"
    "woff2" -> "font/woff2"
    _ -> "text/plain; charset=utf-8"
  }
}

fn extension(path: String) -> String {
  case string.split(path, ".") |> list.last {
    Ok(ext) -> string.lowercase(ext)
    Error(_) -> ""
  }
}

fn not_found() -> Response(BytesBuilder) {
  response.new(404)
  |> response.prepend_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(bytes_builder.from_string("not found"))
}
