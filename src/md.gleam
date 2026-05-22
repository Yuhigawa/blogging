import gleam/int
import gleam/list
import gleam/string

pub fn to_html(source: String) -> String {
  source
  |> string.split("\n")
  |> blocks([], [])
  |> list.reverse
  |> string.join("\n")
}

// Group lines into blocks separated by blank lines.
fn blocks(
  lines: List(String),
  current: List(String),
  out: List(String),
) -> List(String) {
  case lines {
    [] -> flush(current, out)
    [line, ..rest] ->
      case string.trim(line) {
        "" -> blocks(rest, [], flush(current, out))
        _ -> blocks(rest, [line, ..current], out)
      }
  }
}

fn flush(current: List(String), out: List(String)) -> List(String) {
  case current {
    [] -> out
    _ -> [render_block(list.reverse(current)), ..out]
  }
}

fn render_block(lines: List(String)) -> String {
  case lines {
    [single] -> render_single_or_heading(single)
    _ -> "<p>" <> escape(string.join(lines, " ")) <> "</p>"
  }
}

fn render_single_or_heading(line: String) -> String {
  case heading_level(line) {
    Ok(#(n, rest)) ->
      "<h"
      <> int.to_string(n)
      <> ">"
      <> escape(rest)
      <> "</h"
      <> int.to_string(n)
      <> ">"
    Error(_) -> "<p>" <> escape(line) <> "</p>"
  }
}

fn heading_level(line: String) -> Result(#(Int, String), Nil) {
  let trimmed = string.trim_left(line)
  case count_hashes(trimmed, 0) {
    0 -> Error(Nil)
    n if n > 6 -> Error(Nil)
    n -> {
      let rest = string.drop_left(trimmed, n)
      case string.starts_with(rest, " ") {
        True -> Ok(#(n, string.trim(rest)))
        False -> Error(Nil)
      }
    }
  }
}

fn count_hashes(s: String, n: Int) -> Int {
  case string.first(s) {
    Ok("#") -> count_hashes(string.drop_left(s, 1), n + 1)
    _ -> n
  }
}

pub fn escape(s: String) -> String {
  s
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}
