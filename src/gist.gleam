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

/// Stub. Real implementation lands in Task 4 (fake client) and Task 5 (live client).
pub fn fetch_all(
  _client: HttpClient,
  _user: String,
) -> Result(List(Post), GistError) {
  Error(NetworkError("not implemented"))
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
