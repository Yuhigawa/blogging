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

pub fn ul_test() {
  md.to_html("- one\n- two")
  |> should.equal("<ul><li>one</li>\n<li>two</li></ul>")
}

pub fn ul_star_test() {
  md.to_html("* one\n* two")
  |> should.equal("<ul><li>one</li>\n<li>two</li></ul>")
}

pub fn ol_test() {
  md.to_html("1. one\n2. two")
  |> should.equal("<ol><li>one</li>\n<li>two</li></ol>")
}

pub fn list_item_has_inline_test() {
  md.to_html("- **a** b")
  |> should.equal("<ul><li><strong>a</strong> b</li></ul>")
}

pub fn fence_test() {
  md.to_html("```\nfn x() {}\n```")
  |> should.equal("<pre><code>fn x() {}</code></pre>")
}

pub fn fence_escapes_html_test() {
  md.to_html("```\n<script>\n```")
  |> should.equal("<pre><code>&lt;script&gt;</code></pre>")
}

pub fn fence_preserves_internal_blank_line_test() {
  md.to_html("```\na\n\nb\n```")
  |> should.equal("<pre><code>a\n\nb</code></pre>")
}

pub fn blockquote_test() {
  md.to_html("> quoted")
  |> should.equal("<blockquote><p>quoted</p></blockquote>")
}

pub fn hr_test() {
  md.to_html("---") |> should.equal("<hr>")
}

pub fn code_span_suppresses_link_test() {
  md.to_html("`[x](y)`")
  |> should.equal("<p><code>[x](y)</code></p>")
}

pub fn link_href_star_protected_test() {
  md.to_html("[plain](url*with*star)")
  |> should.equal("<p><a href=\"url*with*star\">plain</a></p>")
}

pub fn link_text_can_have_emphasis_test() {
  md.to_html("[*emp*](url)")
  |> should.equal("<p><a href=\"url\"><em>emp</em></a></p>")
}

// T6a edge cases
pub fn heading_seven_hashes_is_paragraph_test() {
  md.to_html("####### Seven")
  |> should.equal("<p>####### Seven</p>")
}

pub fn heading_without_space_is_paragraph_test() {
  md.to_html("#NoSpace")
  |> should.equal("<p>#NoSpace</p>")
}

pub fn heading_with_only_space_is_empty_h1_test() {
  md.to_html("# ")
  |> should.equal("<h1></h1>")
}

// T6b inline edge cases
pub fn unmatched_asterisk_renders_literally_test() {
  md.to_html("*foo")
  |> should.equal("<p>*foo</p>")
}

// Pin: split_last greedy emphasis — first '*' opens, LAST '*' closes,
// so adjacent emphasis runs collapse into a single span.
pub fn two_emphasis_runs_on_one_line_test() {
  md.to_html("*a* *b*")
  |> should.equal("<p><em>a* *b</em></p>")
}

pub fn code_span_inside_bold_test() {
  md.to_html("**a `b` c**")
  |> should.equal("<p><strong>a <code>b</code> c</strong></p>")
}

pub fn heading_with_emphasis_test() {
  md.to_html("# **Bold**")
  |> should.equal("<h1><strong>Bold</strong></h1>")
}

// T6e fence edge cases
// Pin: EOF inside an open fence still flushes accumulated lines as a fence.
pub fn fence_with_eof_inside_test() {
  md.to_html("```\nfoo\nbar")
  |> should.equal("<pre><code>foo\nbar</code></pre>")
}

pub fn empty_fence_test() {
  md.to_html("```\n```")
  |> should.equal("<pre><code></code></pre>")
}

// Pin: language hints are not supported. ```python is not recognized as a
// fence opener; the line is treated inline, producing degenerate output.
pub fn fence_with_language_hint_is_paragraph_test() {
  md.to_html("```python\nfoo\n```")
  |> should.equal("<p><code></code>`python foo</p>\n<pre><code></code></pre>")
}
