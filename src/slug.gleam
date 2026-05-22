import gleam/list
import gleam/string

/// Slugify a string for use as a stable identifier: lowercase, spaces become
/// `-`, and any grapheme outside `[a-z0-9_-]` is dropped.
///
/// Single source of truth for the slug algorithm shared between
/// `gist.dedupe` (which keys on `slugify(group)/slugify(leaf)`) and
/// `menu_render` (which emits `id="..."` from the same slug). These MUST
/// stay aligned — otherwise dedupe-passed posts can collapse into duplicate
/// template ids downstream.
pub fn slugify(s: String) -> String {
  s
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.to_graphemes
  |> list.filter(fn(c) { is_alnum(c) || c == "-" || c == "_" })
  |> string.concat
}

fn is_alnum(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9" -> True
    _ -> False
  }
}
