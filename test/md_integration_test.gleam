import gleeunit/should
import md

pub fn cumulative_integration_test() {
  let input =
    "# Hello\n"
    <> "\n"
    <> "A paragraph with **bold**, `code`, and a [link](https://example.com).\n"
    <> "Also <script>alert(1)</script>.\n"
    <> "\n"
    <> "- one\n"
    <> "- two\n"
    <> "\n"
    <> "1. first\n"
    <> "2. second\n"
    <> "\n"
    <> "```\n"
    <> "fn f() { return 1; }\n"
    <> "```\n"
    <> "\n"
    <> "> a quote\n"
    <> "\n"
    <> "---\n"

  let expected =
    "<h1>Hello</h1>\n"
    <> "<p>A paragraph with <strong>bold</strong>, <code>code</code>, and a <a href=\"https://example.com\">link</a>. Also &lt;script&gt;alert(1)&lt;/script&gt;.</p>\n"
    <> "<ul><li>one</li>\n<li>two</li></ul>\n"
    <> "<ol><li>first</li>\n<li>second</li></ol>\n"
    <> "<pre><code>fn f() { return 1; }</code></pre>\n"
    <> "<blockquote><p>a quote</p></blockquote>\n"
    <> "<hr>"

  md.to_html(input) |> should.equal(expected)
}
