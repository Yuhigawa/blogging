import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/result

/// Typed error returned by `read_text` and `list_dir`. The FFI maps the most
/// common `file` errors to dedicated variants; anything else is folded into
/// `Other` with a short, log-only message (the original reason is not
/// surfaced to callers — they should not be branching on free-form strings).
pub type FileError {
  NotFound
  Permission
  Other(String)
}

@external(erlang, "markdown_server_ffi", "read_text_file")
fn ffi_read(path: String) -> Result(String, Dynamic)

@external(erlang, "markdown_server_ffi", "list_dir")
fn ffi_list(path: String) -> Result(List(String), Dynamic)

/// Read a UTF-8 text file. Errors are normalized to `FileError`.
pub fn read_text(path: String) -> Result(String, FileError) {
  ffi_read(path) |> result.map_error(decode_error)
}

/// List entries of a directory (file and sub-directory names, no path prefix).
/// Errors are normalized to `FileError`.
pub fn list_dir(path: String) -> Result(List(String), FileError) {
  ffi_list(path) |> result.map_error(decode_error)
}

/// Test-only re-export so the malformed-input decode path can be exercised
/// without going through the FFI. Not part of the public consumer API.
pub fn decode_error_for_test(d: Dynamic) -> FileError {
  decode_error(d)
}

// --- internals --------------------------------------------------------------

fn decode_error(d: Dynamic) -> FileError {
  // The FFI returns one of three shapes inside the Error arm:
  //   - atom `not_found`
  //   - atom `permission`
  //   - tuple `{other, Binary}` (Binary is a UTF-8 string)
  // Anything else (a stray tuple, a list, a bare term we did not anticipate)
  // is normalized to a fixed Other message so the caller never has to think
  // about whether the FFI was the source of breakage.
  case atom.from_dynamic(d) {
    Ok(a) -> decode_atom_error(a)
    Error(_) -> decode_tuple_error(d)
  }
}

fn decode_atom_error(a: Atom) -> FileError {
  case atom.to_string(a) {
    "not_found" -> NotFound
    "permission" -> Permission
    _ -> unrecognized()
  }
}

fn decode_tuple_error(d: Dynamic) -> FileError {
  case dynamic.tuple2(atom.from_dynamic, dynamic.string)(d) {
    Ok(#(tag, message)) ->
      case atom.to_string(tag) {
        "other" -> Other(message)
        _ -> unrecognized()
      }
    Error(_) -> unrecognized()
  }
}

fn unrecognized() -> FileError {
  Other("unrecognized: see logs")
}
