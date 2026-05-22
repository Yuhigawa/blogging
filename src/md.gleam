import gleam/int
import gleam/list
import gleam/string

pub fn to_html(source: String) -> String {
  source
  |> string.split("\n")
  |> blocks([], [], Normal)
  |> list.reverse
  |> string.join("\n")
}

type Mode {
  Normal
  InFence(List(String))
}

// Group lines into blocks separated by blank lines.
fn blocks(
  lines: List(String),
  current: List(String),
  out: List(String),
  mode: Mode,
) -> List(String) {
  case mode, lines {
    Normal, [] -> flush(current, out)
    Normal, [line, ..rest] ->
      case string.trim(line) {
        "```" -> blocks(rest, [], flush(current, out), InFence([]))
        "" -> blocks(rest, [], flush(current, out), Normal)
        _ -> blocks(rest, [line, ..current], out, Normal)
      }
    InFence(acc), [] -> [render_fence(list.reverse(acc)), ..out]
    InFence(acc), [line, ..rest] ->
      case string.trim(line) == "```" {
        True ->
          blocks(rest, [], [render_fence(list.reverse(acc)), ..out], Normal)
        False -> blocks(rest, [], out, InFence([line, ..acc]))
      }
  }
}

fn render_fence(lines: List(String)) -> String {
  "<pre><code>" <> escape(string.join(lines, "\n")) <> "</code></pre>"
}

fn flush(current: List(String), out: List(String)) -> List(String) {
  case current {
    [] -> out
    _ -> [render_block(list.reverse(current)), ..out]
  }
}

fn render_block(lines: List(String)) -> String {
  case lines {
    ["---"] -> "<hr>"
    _ ->
      case classify_block(lines) {
        Unordered(items) -> render_list("ul", items)
        Ordered(items) -> render_list("ol", items)
        Blockquote(inner) -> render_blockquote(inner)
        Paragraph ->
          case lines {
            [single] -> render_single_or_heading(single)
            _ ->
              "<p>" <> apply_inline(escape(string.join(lines, " "))) <> "</p>"
          }
      }
  }
}

type BlockKind {
  Unordered(List(String))
  Ordered(List(String))
  Blockquote(List(String))
  Paragraph
}

fn classify_block(lines: List(String)) -> BlockKind {
  case list.all(lines, is_ul_line) {
    True -> Unordered(list.map(lines, strip_ul_marker))
    False ->
      case list.all(lines, is_ol_line) {
        True -> Ordered(list.map(lines, strip_ol_marker))
        False ->
          case list.all(lines, is_bq_line) {
            True -> Blockquote(list.map(lines, strip_bq_marker))
            False -> Paragraph
          }
      }
  }
}

fn is_bq_line(line: String) -> Bool {
  string.starts_with(line, "> ") || line == ">"
}

fn strip_bq_marker(line: String) -> String {
  case line == ">" {
    True -> ""
    False -> string.drop_left(line, 2)
  }
}

fn render_blockquote(lines: List(String)) -> String {
  let inner = to_html(string.join(lines, "\n"))
  "<blockquote>" <> inner <> "</blockquote>"
}

fn is_ul_line(line: String) -> Bool {
  string.starts_with(line, "- ") || string.starts_with(line, "* ")
}

fn strip_ul_marker(line: String) -> String {
  string.drop_left(line, 2)
}

fn is_ol_line(line: String) -> Bool {
  case string.split_once(line, ". ") {
    Error(_) -> False
    Ok(#(head, _)) -> is_all_digits(head)
  }
}

fn strip_ol_marker(line: String) -> String {
  case string.split_once(line, ". ") {
    Ok(#(_, rest)) -> rest
    Error(_) -> line
  }
}

fn is_all_digits(s: String) -> Bool {
  case s {
    "" -> False
    _ -> s |> string.to_graphemes |> list.all(is_digit)
  }
}

fn is_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn render_list(tag: String, items: List(String)) -> String {
  let item_html =
    items
    |> list.map(fn(body) { "<li>" <> apply_inline(escape(body)) <> "</li>" })
    |> string.join("\n")
  "<" <> tag <> ">" <> item_html <> "</" <> tag <> ">"
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
  |> apply_links
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

fn apply_links(s: String) -> String {
  case string.split_once(s, "[") {
    Error(_) -> s
    Ok(#(before, rest)) ->
      case string.split_once(rest, "](") {
        Error(_) -> before <> "[" <> apply_links(rest)
        Ok(#(text, after)) ->
          case string.split_once(after, ")") {
            Error(_) -> before <> "[" <> text <> "](" <> apply_links(after)
            Ok(#(href, tail)) ->
              before
              <> "<a href=\""
              <> escape_attr(href)
              <> "\">"
              <> text
              <> "</a>"
              <> apply_links(tail)
          }
      }
  }
}

fn escape_attr(s: String) -> String {
  s
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
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
