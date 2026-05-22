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

pub fn bold_test() {
  md.to_html("a **bold** b") |> should.equal("<p>a <strong>bold</strong> b</p>")
}

pub fn italic_test() {
  md.to_html("a *italic* b") |> should.equal("<p>a <em>italic</em> b</p>")
}

pub fn code_span_test() {
  md.to_html("`code`") |> should.equal("<p><code>code</code></p>")
}

pub fn code_span_escapes_html_test() {
  md.to_html("`<x>`") |> should.equal("<p><code>&lt;x&gt;</code></p>")
}

pub fn code_span_suppresses_emphasis_test() {
  md.to_html("`**not bold**`")
  |> should.equal("<p><code>**not bold**</code></p>")
}

pub fn backslash_escape_star_test() {
  md.to_html("a \\*literal\\* b")
  |> should.equal("<p>a *literal* b</p>")
}

// Intentional non-support pin: nested emphasis renders literally.
pub fn nested_emphasis_renders_literally_test() {
  md.to_html("**bold *italic***")
  |> should.equal("<p><strong>bold *italic*</strong></p>")
}

pub fn link_test() {
  md.to_html("[Hex](https://hex.pm)")
  |> should.equal("<p><a href=\"https://hex.pm\">Hex</a></p>")
}

pub fn link_text_is_escaped_test() {
  md.to_html("[<x>](https://h)")
  |> should.equal("<p><a href=\"https://h\">&lt;x&gt;</a></p>")
}

pub fn link_href_quote_escaped_test() {
  md.to_html("[t](\"weird)")
  |> should.equal("<p><a href=\"&quot;weird\">t</a></p>")
}
