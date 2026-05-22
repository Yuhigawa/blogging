import file_io
import gleam/list
import gleam/result
import gleam/string

pub type Scan =
  List(#(String, String, String))

//                   group   leaf    body

pub fn scan(root: String) -> Result(Scan, file_io.FileError) {
  use groups <- result.try(file_io.list_dir(root))
  let groups = groups |> list.sort(by: string.compare)
  let entries =
    list.flat_map(groups, fn(g) {
      case is_visible(g) {
        False -> []
        True -> scan_group(root, g)
      }
    })
  Ok(entries)
}

fn scan_group(root: String, group: String) -> Scan {
  let dir = root <> "/" <> group
  case file_io.list_dir(dir) {
    Error(_) -> []
    Ok(files) ->
      files
      |> list.filter(is_post_file)
      |> list.sort(by: string.compare)
      |> list.filter_map(fn(f) { load_post(dir, group, f) })
  }
}

fn load_post(
  dir: String,
  group: String,
  file: String,
) -> Result(#(String, String, String), Nil) {
  let path = dir <> "/" <> file
  case file_io.read_text(path) {
    Error(_) -> Error(Nil)
    Ok(body) -> {
      let leaf = file |> string.replace(each: ".md", with: "")
      Ok(#(group, leaf, body))
    }
  }
}

fn is_visible(name: String) -> Bool {
  !string.starts_with(name, ".")
}

fn is_post_file(name: String) -> Bool {
  is_visible(name) && string.ends_with(name, ".md") && name != "README.md"
}
