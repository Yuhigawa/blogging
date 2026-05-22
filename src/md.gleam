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
    _ -> "<p>" <> apply_inline(escape(string.join(lines, " "))) <> "</p>"
  }
}

fn render_single_or_heading(line: String) -> String {
  case heading_level(line) {
    Ok(#(n, rest)) ->
      "<h"
      <> int.to_string(n)
      <> ">"
      <> apply_inline(escape(rest))
      <> "</h"
      <> int.to_string(n)
      <> ">"
    Error(_) -> "<p>" <> apply_inline(escape(line)) <> "</p>"
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

fn apply_inline(text: String) -> String {
  text
  |> protect_escapes
  |> tokenize_code_spans
  |> resolve_emphasis
  |> restore_escapes
}

const esc_star = "\u{E000}"

const esc_tick = "\u{E001}"

fn protect_escapes(s: String) -> String {
  s
  |> string.replace("\\*", esc_star)
  |> string.replace("\\`", esc_tick)
}

fn restore_escapes(s: String) -> String {
  s
  |> string.replace(esc_star, "*")
  |> string.replace(esc_tick, "`")
}

fn tokenize_code_spans(s: String) -> String {
  case string.split_once(s, "`") {
    Error(_) -> s
    Ok(#(before, rest)) ->
      case string.split_once(rest, "`") {
        Error(_) -> before <> "`" <> tokenize_code_spans(rest)
        Ok(#(code, after)) ->
          before
          <> "<code>"
          <> string.replace(code, "*", esc_star)
          <> "</code>"
          <> tokenize_code_spans(after)
      }
  }
}

fn resolve_emphasis(s: String) -> String {
  s
  |> wrap_runs("**", "strong")
  |> wrap_runs("*", "em")
}

fn wrap_runs(s: String, delim: String, tag: String) -> String {
  case string.split_once(s, delim) {
    Error(_) -> s
    Ok(#(before, rest)) ->
      case split_last(rest, delim) {
        Error(_) -> before <> delim <> wrap_runs(rest, delim, tag)
        Ok(#(inner, after)) ->
          before
          <> "<"
          <> tag
          <> ">"
          <> string.replace(inner, "*", esc_star)
          <> "</"
          <> tag
          <> ">"
          <> wrap_runs(after, delim, tag)
      }
  }
}

fn split_last(s: String, delim: String) -> Result(#(String, String), Nil) {
  let dlen = string.length(delim)
  let slen = string.length(s)
  case slen < dlen {
    True -> Error(Nil)
    False -> split_last_loop(s, delim, dlen, slen - dlen)
  }
}

fn split_last_loop(
  s: String,
  delim: String,
  dlen: Int,
  i: Int,
) -> Result(#(String, String), Nil) {
  case i < 0 {
    True -> Error(Nil)
    False -> {
      let candidate = string.slice(s, i, dlen)
      case candidate == delim {
        True ->
          Ok(#(
            string.slice(s, 0, i),
            string.slice(s, i + dlen, string.length(s) - i - dlen),
          ))
        False -> split_last_loop(s, delim, dlen, i - 1)
      }
    }
  }
}
