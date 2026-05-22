import file_io
import gleam/dynamic
import gleam/erlang/atom
import gleam/list
import gleeunit/should

pub fn read_text_existing_file_test() {
  let assert Ok(content) = file_io.read_text("test/fixtures/file_io/hello.txt")
  content
  |> should.equal("hello fixture")
}

pub fn read_text_missing_file_test() {
  file_io.read_text("test/fixtures/file_io/__definitely_missing__.md")
  |> should.equal(Error(file_io.NotFound))
}

pub fn list_dir_existing_test() {
  let assert Ok(entries) = file_io.list_dir("test/fixtures/file_io")
  // hello.txt exists in the fixtures dir, so it must show up in the listing.
  should.be_true(list.contains(entries, "hello.txt"))
}

pub fn list_dir_missing_test() {
  file_io.list_dir("test/fixtures/file_io/__definitely_missing_dir__")
  |> should.equal(Error(file_io.NotFound))
}

pub fn decode_error_malformed_tuple_test() {
  // A 3-tuple of strings — wrong arity for the 2-tuple decoder. The decoder
  // must classify this as Other("unrecognized: see logs") instead of crashing.
  let weird = dynamic.from(#("weird", "extra", "stuff"))

  file_io.decode_error_for_test(weird)
  |> should.equal(file_io.Other("unrecognized: see logs"))
}

pub fn decode_error_unrecognized_atom_test() {
  // An atom that is not one of the FFI's known tags (`not_found`,
  // `permission`) — exercises the atom-path fall-through.
  let weird = dynamic.from(atom.create_from_string("weird"))

  file_io.decode_error_for_test(weird)
  |> should.equal(file_io.Other("unrecognized: see logs"))
}

pub fn decode_error_permission_atom_test() {
  // Decoder-seam coverage for the `Permission` variant without needing a
  // portable filesystem permission-denied setup.
  file_io.decode_error_for_test(
    dynamic.from(atom.create_from_string("permission")),
  )
  |> should.equal(file_io.Permission)
}
