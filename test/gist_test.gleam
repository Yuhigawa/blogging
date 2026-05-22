import file_io
import gist
import gleam/erlang/os
import gleam/list
import gleeunit/should

pub fn parse_filename_accepts_blog_prefix_test() {
  gist.parse_filename_for_test("blog:estudos:html.md")
  |> should.equal(Ok(#("estudos", "html")))
}

pub fn parse_filename_accepts_spaces_in_parts_test() {
  gist.parse_filename_for_test("blog:Estudos:HTML Intro.md")
  |> should.equal(Ok(#("Estudos", "HTML Intro")))
}

pub fn parse_filename_rejects_non_blog_prefix_test() {
  gist.parse_filename_for_test("README.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_empty_group_test() {
  gist.parse_filename_for_test("blog::foo.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_empty_leaf_test() {
  gist.parse_filename_for_test("blog:estudos:.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_no_md_suffix_test() {
  gist.parse_filename_for_test("blog:estudos:html")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_wrong_suffix_test() {
  gist.parse_filename_for_test("blog:estudos:html.txt")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_three_colons_test() {
  gist.parse_filename_for_test("blog:a:b:c.md")
  |> should.equal(Error(Nil))
}

pub fn parse_filename_rejects_plain_text_test() {
  gist.parse_filename_for_test("notes.md")
  |> should.equal(Error(Nil))
}

fn ok_client(
  list_json: String,
  bodies: List(#(String, String)),
) -> gist.HttpClient {
  gist.HttpClient(list_gists: fn(_user) { Ok(list_json) }, fetch_raw: fn(url) {
    case list.key_find(bodies, url) {
      Ok(body) -> Ok(body)
      Error(_) -> Error(gist.HttpError(404))
    }
  })
}

pub fn fetch_all_returns_sorted_posts_test() {
  let assert Ok(list_json) = file_io.read_text("test/fixtures/gist_list.json")
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
      "# html\nbody",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:css.md",
      "# css\nbody",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/def456/raw/blog:ensaios:opening.md",
      "# opening\nbody",
    ),
  ]
  let assert Ok(posts) =
    gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  // Sorted by (slug(group), slug(leaf)). ensaios < estudos; within estudos: css < html.
  list.length(posts) |> should.equal(3)
  let assert Ok(p0) = list.first(posts)
  p0.group |> should.equal("ensaios")
  p0.leaf |> should.equal("opening")
  let assert Ok(p1) = list_at(posts, 1)
  p1.group |> should.equal("estudos")
  p1.leaf |> should.equal("css")
  let assert Ok(p2) = list_at(posts, 2)
  p2.group |> should.equal("estudos")
  p2.leaf |> should.equal("html")
}

pub fn fetch_all_filters_non_blog_files_test() {
  let assert Ok(list_json) = file_io.read_text("test/fixtures/gist_list.json")
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
      "x",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:css.md",
      "x",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/def456/raw/blog:ensaios:opening.md",
      "x",
    ),
  ]
  let assert Ok(posts) =
    gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  list.any(posts, fn(p) { p.leaf == "notes" }) |> should.be_false
}

pub fn fetch_all_total_failure_on_list_error_test() {
  let client =
    gist.HttpClient(
      list_gists: fn(_) { Error(gist.NetworkError("connection refused")) },
      fetch_raw: fn(_) { Ok("never called") },
    )
  gist.fetch_all(client, "Yuhigawa")
  |> should.equal(Error(gist.NetworkError("connection refused")))
}

pub fn fetch_all_partial_failure_drops_failed_post_test() {
  let assert Ok(list_json) = file_io.read_text("test/fixtures/gist_list.json")
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
      "# html\nbody",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/def456/raw/blog:ensaios:opening.md",
      "# opening\nbody",
    ),
  ]
  let assert Ok(posts) =
    gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  list.length(posts) |> should.equal(2)
  list.any(posts, fn(p) { p.leaf == "css" }) |> should.be_false
}

pub fn fetch_all_collision_first_wins_test() {
  let list_json =
    "[
      {\"id\": \"first\",  \"files\": {\"blog:dup:x.md\": {\"filename\": \"blog:dup:x.md\"}}},
      {\"id\": \"second\", \"files\": {\"blog:dup:x.md\": {\"filename\": \"blog:dup:x.md\"}}}
    ]"
  let bodies = [
    #(
      "https://gist.githubusercontent.com/Yuhigawa/first/raw/blog:dup:x.md",
      "WIN",
    ),
    #(
      "https://gist.githubusercontent.com/Yuhigawa/second/raw/blog:dup:x.md",
      "LOSE",
    ),
  ]
  let assert Ok(posts) =
    gist.fetch_all(ok_client(list_json, bodies), "Yuhigawa")
  list.length(posts) |> should.equal(1)
  let assert Ok(p) = list.first(posts)
  p.body |> should.equal("WIN")
}

pub fn build_raw_url_test() {
  gist.build_raw_url_for_test("Yuhigawa", "abc123", "blog:estudos:html.md")
  |> should.equal(
    "https://gist.githubusercontent.com/Yuhigawa/abc123/raw/blog:estudos:html.md",
  )
}

fn list_at(xs: List(a), i: Int) -> Result(a, Nil) {
  list.drop(xs, i) |> list.first
}

pub fn live_fetch_yuhigawa_test() {
  case os.get_env("BLOG_LIVE_TEST") {
    Ok("1") -> {
      let client = gist.live_client()
      case gist.fetch_all(client, "Yuhigawa") {
        Ok(posts) -> should.be_true(list.length(posts) >= 0)
        Error(err) ->
          // Surface the failure if the live wiring actually broke.
          should.equal(err, gist.NetworkError("live test expected Ok"))
      }
    }
    _ -> should.be_true(True)
  }
}
