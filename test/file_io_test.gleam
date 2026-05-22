import file_io
import gleam/dynamic
import gleam/list
import gleeunit/should

pub fn read_text_existing_file_test() {
  let assert Ok(content) = file_io.read_text("src/assets/index.html")
  // Sanity check: index.html is non-empty.
  should.be_true(content != "")
}

pub fn read_text_missing_file_test() {
  file_io.read_text("src/assets/__definitely_missing__.md")
  |> should.equal(Error(file_io.NotFound))
}

pub fn list_dir_existing_test() {
  let assert Ok(entries) = file_io.list_dir("src/assets")
  // index.html exists in src/assets/, so it must show up in the listing.
  should.be_true(list.contains(entries, "index.html"))
}

pub fn list_dir_missing_test() {
  file_io.list_dir("src/assets/__definitely_missing_dir__")
  |> should.equal(Error(file_io.NotFound))
}

pub fn decode_error_malformed_test() {
  // {error, weird} unwraps to a Dynamic carrying the atom `weird`, which the
  // decoder must classify as Other("unrecognized: see logs") instead of crashing.
  let weird = dynamic.from(#("weird", "extra", "stuff"))

  file_io.decode_error_for_test(weird)
  |> should.equal(file_io.Other("unrecognized: see logs"))
}
