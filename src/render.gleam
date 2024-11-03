import gleam/list
import gleam/string

@external(erlang, "markdown_server_ffi", "read_text_file")
fn read_text_file(path: String) -> Result(String, String)

pub fn convert_markdown_to_html(file_path: String) -> String {
  let full_file_path = "src/assets/" <> file_path

  case read_text_file(full_file_path) {
    Ok(content) -> parse_markdown(content, file_path)
    Error(_) -> "<h1>Error reading file</h1>"
  }
}

pub fn file_to_string(file_path: String) -> String {
  let full_file_path = "src/assets/" <> file_path

  case read_text_file(full_file_path) {
    Ok(content) -> content
    Error(_) -> "<h1>Error reading file to string<h1>"
  }
}

fn flatten_strings(lines: List(String), line: String) -> List(String) {
  let length = list.length(lines)

  list.flatten([
    list.take(lines, length - 1),
    [line],
    list.drop(lines, length - 1),
  ])
}

pub fn concatenate_templates(content: String, templates: List(String)) -> String {
  let lines = string.split(content, "\n")
  let parsed_templates = list.map(templates, convert_markdown_to_html)

  let updated_lines = list.fold(parsed_templates, lines, flatten_strings)
  string.join(updated_lines, "\n")
}

fn get_first_segment(file_name: String) -> String {
  case string.split(file_name, ".") {
    [first, ..] -> first
    [] -> ""
  }
}

fn parse_markdown(content: String, file_name: String) -> String {
  let parsed_content =
    content
    |> string.split("\n")
    |> list.map(parse_line)
    |> string.join("\n")

  string.replace("<template id=template-@>", "@", get_first_segment(file_name))
  <> parsed_content
  <> "</template>"
}

fn parse_line(line: String) -> String {
  let trimmed_line = string.trim(line)

  case string.starts_with(trimmed_line, "# ") {
    True ->
      "<h1>"
      <> string.slice(trimmed_line, 2, string.length(trimmed_line))
      <> "</h1>"
    False ->
      case string.starts_with(trimmed_line, "## ") {
        True ->
          "<h2>"
          <> string.slice(trimmed_line, 3, string.length(trimmed_line))
          <> "</h2>"
        False -> "<p>" <> trimmed_line <> "</p>"
      }
  }
}
