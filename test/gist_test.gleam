import gist
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
