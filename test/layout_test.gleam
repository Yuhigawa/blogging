import gleeunit/should
import layout

pub fn splices_menu_and_templates_test() {
  let tpl =
    "<nav><!-- {{menu}} --></nav><div><!-- {{banner}} --></div><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "<ul>M</ul>", "<template>T</template>", "")
  should.equal(
    out,
    "<nav><ul>M</ul></nav><div></div><body><template>T</template></body>",
  )
}

pub fn missing_menu_placeholder_raises_test() {
  let tpl = "<body><!-- {{templates}} --></body><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.MissingMenu))
}

pub fn missing_templates_placeholder_raises_test() {
  let tpl = "<nav><!-- {{menu}} --></nav><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.MissingTemplates))
}

pub fn duplicate_menu_placeholder_raises_test() {
  let tpl =
    "<!-- {{menu}} --><!-- {{menu}} --><!-- {{templates}} --><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateMenu))
}

pub fn duplicate_templates_placeholder_raises_test() {
  let tpl =
    "<!-- {{menu}} --><!-- {{templates}} --><!-- {{templates}} --><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateTemplates))
}

pub fn missing_banner_placeholder_raises_test() {
  let tpl = "<!-- {{menu}} --><!-- {{templates}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.MissingBanner))
}

pub fn duplicate_banner_placeholder_raises_test() {
  let tpl =
    "<!-- {{menu}} --><!-- {{templates}} --><!-- {{banner}} --><!-- {{banner}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateBanner))
}

pub fn render_substitutes_banner_test() {
  let tpl =
    "<nav><!-- {{menu}} --></nav><div><!-- {{banner}} --></div><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "M", "T", "BAN")
  should.equal(out, "<nav>M</nav><div>BAN</div><body>T</body>")
}

pub fn render_empty_banner_collapses_test() {
  let tpl =
    "<nav><!-- {{menu}} --></nav><div><!-- {{banner}} --></div><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "M", "T", "")
  should.equal(out, "<nav>M</nav><div></div><body>T</body>")
}
