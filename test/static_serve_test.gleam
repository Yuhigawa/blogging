import gleam/option.{None, Some}
import gleeunit/should
import static_serve

pub fn mime_css_test() {
  static_serve.mime_for("foo.css") |> should.equal("text/css; charset=utf-8")
}

pub fn mime_unknown_test() {
  static_serve.mime_for("foo.bin") |> should.equal("text/plain; charset=utf-8")
}

pub fn resolve_normal_test() {
  static_serve.resolve("styles.css")
  |> should.equal(Some("src/assets/static/styles.css"))
}

pub fn resolve_traversal_rejected_test() {
  static_serve.resolve("../../etc/passwd") |> should.equal(None)
}

pub fn resolve_absolute_rejected_test() {
  static_serve.resolve("/etc/passwd") |> should.equal(None)
}
