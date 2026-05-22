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
