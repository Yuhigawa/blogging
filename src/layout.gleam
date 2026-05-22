import gleam/list
import gleam/string

pub type LayoutError {
  MissingMenu
  MissingTemplates
  MissingBanner
  DuplicateMenu
  DuplicateTemplates
  DuplicateBanner
}

const menu_token = "<!-- {{menu}} -->"

const templates_token = "<!-- {{templates}} -->"

const banner_token = "<!-- {{banner}} -->"

pub fn validate(template: String) -> Result(Nil, LayoutError) {
  let menu_count = count_occurrences(template, menu_token)
  let tpls_count = count_occurrences(template, templates_token)
  let banner_count = count_occurrences(template, banner_token)
  case menu_count, tpls_count, banner_count {
    0, _, _ -> Error(MissingMenu)
    _, 0, _ -> Error(MissingTemplates)
    _, _, 0 -> Error(MissingBanner)
    n, _, _ if n > 1 -> Error(DuplicateMenu)
    _, n, _ if n > 1 -> Error(DuplicateTemplates)
    _, _, n if n > 1 -> Error(DuplicateBanner)
    _, _, _ -> Ok(Nil)
  }
}

pub fn render(
  template: String,
  menu_html: String,
  templates_html: String,
  banner_html: String,
) -> String {
  template
  |> string.replace(menu_token, menu_html)
  |> string.replace(templates_token, templates_html)
  |> string.replace(banner_token, banner_html)
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  list.length(parts) - 1
}
