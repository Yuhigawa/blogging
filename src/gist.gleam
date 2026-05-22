import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string

const blog_prefix = "blog:"

const md_suffix = ".md"

pub type Post {
  Post(group: String, leaf: String, body: String)
}

pub type GistError {
  NetworkError(reason: String)
  HttpError(status: Int)
  ParseError(reason: String)
}

pub type HttpClient {
  HttpClient(
    list_gists: fn(String) -> Result(String, GistError),
    fetch_raw: fn(String) -> Result(String, GistError),
  )
}

/// Fetch all `blog:<group>:<leaf>.md` posts authored by `user`, using the
/// supplied `HttpClient` capability for I/O. Pure assembly: list -> decode ->
/// filter -> fetch each body -> sort by (slug(group), slug(leaf)) -> dedupe
/// (first wins). Partial raw-fetch failures are logged and dropped; a
/// list-call failure surfaces to the caller unchanged.
pub fn fetch_all(
  client: HttpClient,
  user: String,
) -> Result(List(Post), GistError) {
  use list_json <- result.try(client.list_gists(user))
  use entries <- result.try(decode_gist_list(list_json))
  let candidates = collect_candidates(entries, user)
  let posts = fetch_bodies(client, candidates)
  Ok(dedupe(sort_by_slug(posts)))
}

/// Test-only re-export. See `build_raw_url`.
pub fn build_raw_url_for_test(
  user: String,
  gist_id: String,
  filename: String,
) -> String {
  build_raw_url(user, gist_id, filename)
}

/// Test-only re-export. See `parse_filename`.
pub fn parse_filename_for_test(name: String) -> Result(#(String, String), Nil) {
  parse_filename(name)
}

/// Returns `Ok(#(group, leaf))` for filenames matching `blog:<group>:<leaf>.md`
/// with non-empty group and leaf, neither containing `:`. Rejects everything else.
fn parse_filename(name: String) -> Result(#(String, String), Nil) {
  use without_prefix <- with_prefix(name, blog_prefix)
  use without_suffix <- with_suffix(without_prefix, md_suffix)
  case string.split(without_suffix, ":") {
    [group, leaf] ->
      case group, leaf {
        "", _ -> Error(Nil)
        _, "" -> Error(Nil)
        _, _ -> Ok(#(group, leaf))
      }
    _ -> Error(Nil)
  }
}

fn with_prefix(
  s: String,
  prefix: String,
  k: fn(String) -> Result(a, Nil),
) -> Result(a, Nil) {
  case string.starts_with(s, prefix) {
    True -> k(string.drop_left(s, string.length(prefix)))
    False -> Error(Nil)
  }
}

fn with_suffix(
  s: String,
  suffix: String,
  k: fn(String) -> Result(a, Nil),
) -> Result(a, Nil) {
  case string.ends_with(s, suffix) {
    True -> k(string.drop_right(s, string.length(suffix)))
    False -> Error(Nil)
  }
}

// --- raw URL ---------------------------------------------------------------

fn build_raw_url(user: String, gist_id: String, filename: String) -> String {
  "https://gist.githubusercontent.com/"
  <> user
  <> "/"
  <> gist_id
  <> "/raw/"
  <> filename
}

// --- decode ----------------------------------------------------------------

type GistEntry {
  GistEntry(id: String, filenames: List(String))
}

fn decode_gist_list(json_str: String) -> Result(List(GistEntry), GistError) {
  let entry_decoder =
    dynamic.decode2(
      GistEntry,
      dynamic.field("id", dynamic.string),
      dynamic.field("files", files_keys_decoder),
    )
  json.decode(from: json_str, using: dynamic.list(entry_decoder))
  |> result.map_error(fn(_) { ParseError("decode error") })
}

fn files_keys_decoder(
  d: Dynamic,
) -> Result(List(String), dynamic.DecodeErrors) {
  // Decode the `files` object as a Dict<String, Dynamic> and project to keys.
  // We intentionally ignore the value side — only filenames are needed.
  dynamic.dict(dynamic.string, dynamic.dynamic)(d)
  |> result.map(dict.keys)
}

// --- assembly --------------------------------------------------------------

fn collect_candidates(
  entries: List(GistEntry),
  user: String,
) -> List(#(String, String, String)) {
  list.flat_map(entries, fn(e) {
    list.filter_map(e.filenames, fn(filename) {
      case parse_filename(filename) {
        Error(_) -> Error(Nil)
        Ok(#(g, l)) -> Ok(#(g, l, build_raw_url(user, e.id, filename)))
      }
    })
  })
}

fn fetch_bodies(
  client: HttpClient,
  candidates: List(#(String, String, String)),
) -> List(Post) {
  list.filter_map(candidates, fn(c) {
    let #(g, l, url) = c
    case client.fetch_raw(url) {
      Ok(body) -> Ok(Post(group: g, leaf: l, body: body))
      Error(err) -> {
        log_warn("fetch_raw failed for " <> url <> ": " <> error_label(err))
        Error(Nil)
      }
    }
  })
}

fn sort_by_slug(posts: List(Post)) -> List(Post) {
  list.sort(posts, by: fn(a, b) {
    let ka = slug(a.group) <> "/" <> slug(a.leaf)
    let kb = slug(b.group) <> "/" <> slug(b.leaf)
    string.compare(ka, kb)
  })
}

fn dedupe(posts: List(Post)) -> List(Post) {
  let #(kept, _seen) =
    list.fold(posts, #([], []), fn(acc, p) {
      let #(kept, seen) = acc
      let key = slug(p.group) <> "/" <> slug(p.leaf)
      case list.contains(seen, key) {
        True -> {
          log_warn("collision dropped: " <> key)
          #(kept, seen)
        }
        False -> #([p, ..kept], [key, ..seen])
      }
    })
  list.reverse(kept)
}

// --- slug + logging --------------------------------------------------------

fn slug(s: String) -> String {
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

fn log_warn(msg: String) -> Nil {
  io.println_error("[gist] " <> msg)
}

fn error_label(err: GistError) -> String {
  case err {
    NetworkError(reason) -> "NetworkError(" <> reason <> ")"
    HttpError(status) -> "HttpError(" <> int.to_string(status) <> ")"
    ParseError(reason) -> "ParseError(" <> reason <> ")"
  }
}
