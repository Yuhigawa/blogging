import gleam/list
import gleam/string

pub type LayoutError {
  MissingMenu
  MissingTemplates
  DuplicateMenu
  DuplicateTemplates
}

const menu_token = "<!-- {{menu}} -->"

const templates_token = "<!-- {{templates}} -->"

pub fn validate(template: String) -> Result(Nil, LayoutError) {
  let menu_count = count_occurrences(template, menu_token)
  let tpls_count = count_occurrences(template, templates_token)
  case menu_count, tpls_count {
    0, _ -> Error(MissingMenu)
    _, 0 -> Error(MissingTemplates)
    n, _ if n > 1 -> Error(DuplicateMenu)
    _, n if n > 1 -> Error(DuplicateTemplates)
    _, _ -> Ok(Nil)
  }
}

pub fn render(
  template: String,
  menu_html: String,
  templates_html: String,
) -> String {
  // Slugify in menu_render strips `<`, `>`, `{`, `}`, so the templates token
  // cannot survive into menu_html — substitution order is safe.
  template
  |> string.replace(menu_token, menu_html)
  |> string.replace(templates_token, templates_html)
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  list.length(parts) - 1
}
