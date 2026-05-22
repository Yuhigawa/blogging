import gleeunit/should
import layout

pub fn splices_menu_and_templates_test() {
  let tpl = "<nav><!-- {{menu}} --></nav><body><!-- {{templates}} --></body>"
  let out = layout.render(tpl, "<ul>M</ul>", "<template>T</template>")
  should.equal(out, "<nav><ul>M</ul></nav><body><template>T</template></body>")
}

pub fn missing_menu_placeholder_raises_test() {
  let tpl = "<body><!-- {{templates}} --></body>"
  layout.validate(tpl) |> should.equal(Error(layout.MissingMenu))
}

pub fn missing_templates_placeholder_raises_test() {
  let tpl = "<nav><!-- {{menu}} --></nav>"
  layout.validate(tpl) |> should.equal(Error(layout.MissingTemplates))
}

pub fn duplicate_menu_placeholder_raises_test() {
  let tpl = "<!-- {{menu}} --><!-- {{menu}} --><!-- {{templates}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateMenu))
}

pub fn duplicate_templates_placeholder_raises_test() {
  let tpl = "<!-- {{menu}} --><!-- {{templates}} --><!-- {{templates}} -->"
  layout.validate(tpl) |> should.equal(Error(layout.DuplicateTemplates))
}
