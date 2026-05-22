import gleeunit/should
import md

pub fn h1_test() {
  md.to_html("# Title") |> should.equal("<h1>Title</h1>")
}

pub fn h6_test() {
  md.to_html("###### Six") |> should.equal("<h6>Six</h6>")
}

pub fn paragraph_test() {
  md.to_html("hello world") |> should.equal("<p>hello world</p>")
}

pub fn blank_line_no_empty_p_test() {
  md.to_html("\n\n") |> should.equal("")
}

pub fn paragraphs_separated_by_blank_line_test() {
  md.to_html("one\n\ntwo") |> should.equal("<p>one</p>\n<p>two</p>")
}

pub fn escape_lt_gt_amp_test() {
  md.to_html("a < b & c > d")
  |> should.equal("<p>a &lt; b &amp; c &gt; d</p>")
}

pub fn script_tag_escaped_test() {
  md.to_html("<script>alert(1)</script>")
  |> should.equal("<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
}
