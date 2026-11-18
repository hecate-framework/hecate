---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- Diagrams (ADR 0033, OQ-128): a fenced block whose info string is `mermaid` stays a readable code block, the
-- renderer flags the page, and only a flagged page loads the vendored library and the initialiser.
local test = require("harness.test")
local doc = require("hecate.doc")
local markdown = require("hecate.doc.markdown")
local T = test.Case("DiagramTest")

local function has(text, part) return text:find(part, 1, true) ~= nil end

local function read(path)
  local file = assert(io.open(path, "rb"), path)
  local text = file:read("a")
  file:close()
  return text
end

local DIAGRAM = "```mermaid\ngraph TD\n  A[\"<b>raw</b>\"] --> B\n```\n"

local function build(files)
  local prefixed = {}
  for path, data in pairs(files) do prefixed["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(prefixed)
  doc.build({
    config = { title = "hecate", locales = { { code = "en", label = "English", lang = "en" } } },
    source = "c", out = "o", fs = fs,
  })
  return fs
end

local function page(title, body) return ("---\ntitle: %s\n---\n%s\n"):format(title, body) end

-- Renderer ------------------------------------------------------------------------------

function T:test_a_mermaid_fence_flags_the_result_and_stays_a_code_block()
  local result = markdown.render(DIAGRAM)
  self:assert_true(result.diagrams)
  self:assert_true(has(result.html, '<div class="code-block" data-language="mermaid">'))
  self:assert_true(has(result.html, "graph TD"), "the diagram source stays in the page without JavaScript")
  self:assert_true(has(result.html, "&lt;b&gt;raw&lt;/b&gt;"), "label text is escaped in the fallback")
  self:assert_nil(result.html:find("<b>raw</b>", 1, true))
end

function T:test_other_blocks_and_mentions_of_the_marker_do_not_flag_the_result()
  self:assert_false(markdown.render("```lua\nlocal x = 1\n```\n").diagrams)
  self:assert_false(markdown.render("```\nplain\n```\n").diagrams)
  self:assert_false(markdown.render("Text about `mermaid` diagrams.\n").diagrams)
  local quoted = markdown.render('```lua\nlocal s = \'<div class="code-block" data-language="mermaid">\'\n```\n')
  self:assert_false(quoted.diagrams, "the marker inside code is escaped text, not a diagram")
  self:assert_false(markdown.render('<div class="code-block" data-language="mermaid"></div>\n').diagrams,
    "raw HTML is not passed through, so a page cannot flag itself")
end

-- Site ----------------------------------------------------------------------------------

function T:test_a_page_with_a_diagram_loads_the_library_and_the_initialiser_after_the_theme()
  local fs = build({ ["en/index.md"] = page("Home", "no diagram"), ["en/a.md"] = page("A", DIAGRAM) })
  local html = fs:read("o/en/a/index.html")
  local theme_at = html:find('src="/assets/theme.js"', 1, true)
  local library_at = html:find('<script src="/assets/mermaid/mermaid.min.js" defer></script>', 1, true)
  local init_at = html:find('<script src="/assets/mermaid-init.js" defer></script>', 1, true)
  self:assert_not_nil(theme_at)
  self:assert_not_nil(library_at)
  self:assert_not_nil(init_at)
  self:assert_true(library_at < init_at, "the library runs before the initialiser (deferred scripts keep their order)")
  self:assert_nil(html:find("https?://[^\"' ]*mermaid"), "no address outside the site")
end

function T:test_the_library_files_are_written_only_when_a_page_holds_a_diagram()
  local with = build({ ["en/index.md"] = page("Home", DIAGRAM) })
  for _, path in ipairs({ "o/assets/mermaid/mermaid.min.js", "o/assets/mermaid/LICENSE", "o/assets/mermaid-init.js" }) do
    self:assert_not_nil(with:read(path), path)
  end
  self:assert_equal(read(doc.theme.assets_directory() .. "/mermaid/mermaid.min.js"),
    with:read("o/assets/mermaid/mermaid.min.js"), "the vendored file is copied unmodified")
  local without = build({ ["en/index.md"] = page("Home", "text only") })
  for _, path in ipairs({ "o/assets/mermaid/mermaid.min.js", "o/assets/mermaid/LICENSE", "o/assets/mermaid-init.js" }) do
    self:assert_nil(without:read(path), path)
  end
  local html = without:read("o/en/index.html")
  self:assert_nil(html:find("mermaid", 1, true), "a page without a diagram does not mention the library")
end

function T:test_a_diagram_on_one_page_does_not_load_the_library_on_the_others()
  local fs = build({ ["en/index.md"] = page("Home", "text"), ["en/a.md"] = page("A", DIAGRAM) })
  self:assert_nil(fs:read("o/en/index.html"):find("mermaid", 1, true))
  self:assert_true(has(fs:read("o/en/a/index.html"), "mermaid-init.js"))
end

-- Theme ---------------------------------------------------------------------------------

function T:test_every_listed_diagram_file_exists()
  self:assert_true(#doc.theme.diagram_files >= 3)
  for _, file in ipairs(doc.theme.diagram_files) do
    self:assert_not_nil(read(doc.theme.assets_directory() .. "/" .. file), file)
  end
end

local INIT = read(doc.theme.assets_directory() .. "/mermaid-init.js")

function T:test_the_initialiser_renders_strictly_and_takes_its_colours_from_the_brand_tokens()
  self:assert_true(has(INIT, 'securityLevel: "strict"'))
  self:assert_true(has(INIT, "startOnLoad: false"), "diagrams are rendered by the initialiser, not by the library on load")
  self:assert_true(has(INIT, "htmlLabels: false"), "labels are SVG text: no HTML from diagram text")
  self:assert_nil(INIT:find("innerHTML", 1, true), "the SVG is parsed and imported, never assigned as markup")
  for _, token in ipairs({ "--surface-100", "--surface-200", "--surface-300", "--ink", "--ink-muted", "--border-strong",
    "--earth" }) do
    self:assert_true(has(INIT, token), token)
  end
  self:assert_nil(INIT:find("#%x%x%x%x%x%x"), "no colour literal: every colour is read from the page's tokens")
  self:assert_true(has(INIT, "data-theme"), "the diagrams are drawn again when the colour theme changes")
end

function T:test_the_initialiser_makes_no_network_request_of_its_own()
  for _, forbidden in ipairs({ "fetch(", "XMLHttpRequest", "import(", "http://", "https://", "sendBeacon" }) do
    self:assert_nil(INIT:find(forbidden, 1, true), forbidden)
  end
end

-- Navigation: toolbar, pan, zoom, full screen (owner request of 2026-11-18) --------------------------------------

local CONTROL_KEYS = { "diagram_controls", "diagram_zoom_in", "diagram_zoom_out", "diagram_reset", "diagram_fullscreen",
  "diagram_exit_fullscreen" }

function T:test_the_control_strings_exist_in_english_and_french_and_are_not_empty()
  local catalogue = doc.theme.strings.catalogue
  for _, key in ipairs(CONTROL_KEYS) do
    for _, locale in ipairs({ "en", "fr" }) do
      self:assert_true(type(catalogue[locale][key]) == "string" and catalogue[locale][key] ~= "", locale .. " " .. key)
    end
    self:assert_true(catalogue.en[key] ~= catalogue.fr[key], key .. " is translated")
  end
end

function T:test_only_a_page_with_a_diagram_carries_the_control_strings_in_its_script_configuration()
  local fs = build({ ["en/index.md"] = page("Home", "text"), ["en/a.md"] = page("A", DIAGRAM) })
  local with = fs:read("o/en/a/index.html")
  local without = fs:read("o/en/index.html")
  for _, key in ipairs(CONTROL_KEYS) do
    self:assert_true(has(with, '"' .. key .. '"'), key)
    self:assert_nil(without:find('"' .. key .. '"', 1, true), key .. " on a page without a diagram")
  end
  self:assert_true(has(with, '"diagram_zoom_in":"Zoom in"'))
end

function T:test_the_french_page_carries_the_french_control_strings()
  local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home", DIAGRAM), ["c/fr/index.md"] = page("Accueil", DIAGRAM) })
  doc.build({
    config = { title = "hecate", locales = { { code = "en", label = "English", lang = "en" },
      { code = "fr", label = "Français", lang = "fr" } } },
    source = "c", out = "o", fs = fs,
  })
  local french = fs:read("o/fr/index.html")
  self:assert_true(has(french, '"diagram_fullscreen":"Plein '), "French label")
  self:assert_true(has(french, "Zoom avant"))
  self:assert_true(has(fs:read("o/en/index.html"), '"diagram_fullscreen":"Full screen"'))
end

function T:test_the_initialiser_builds_the_controls_without_markup_eval_or_inline_handlers()
  for _, forbidden in ipairs({ "innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval(", "new Function",
    'setAttribute("style"', "setAttribute('style'", "setAttribute(\"on", "javascript:", ".onclick", "srcdoc" }) do
    self:assert_nil(INIT:find(forbidden, 1, true), forbidden)
  end
  self:assert_nil(INIT:find("%f[%w]on%l+%s*=%s*[\"']"), "no inline handler attribute")
  for _, part in ipairs({ 'createElement("button")', 'element.type = "button"', "aria-label", "aria-keyshortcuts",
    'role", "toolbar"', "pointerdown", "pointermove", "setPointerCapture", "wheel", "{ passive: false }" }) do
    self:assert_true(has(INIT, part), part)
  end
end

function T:test_the_wheel_zooms_only_with_ctrl_or_cmd_or_in_full_screen()
  self:assert_true(has(INIT, "if (!(state.full || event.ctrlKey || event.metaKey)) return;"),
    "a plain wheel in the page is left to the browser")
end

function T:test_the_full_screen_uses_the_api_when_present_and_an_overlay_class_always()
  for _, part in ipairs({ "requestFullscreen", "webkitRequestFullscreen", "fullscreenchange", "exitFullscreen",
    '"is-fullscreen"', '"diagram-fullscreen"', '"Escape"' }) do
    self:assert_true(has(INIT, part), part)
  end
end

function T:test_the_stylesheet_locks_the_page_on_the_root_element_only_and_the_toolbar_uses_tokens()
  local css = read(doc.theme.assets_directory() .. "/theme.css")
  self:assert_true(has(css, "html.diagram-fullscreen { overflow: hidden; }"))
  self:assert_nil(css:find("body[^{}]*diagram[^{}]*{[^}]*overflow", 1), "never overflow on body")
  self:assert_true(has(css, ".diagram.is-fullscreen { position: fixed; inset: 0;"))
  local toolbar = css:match("\n(%.diagram%-toolbar [^\n]*)")
  self:assert_not_nil(toolbar)
  self:assert_true(has(toolbar, "padding: var(--space-2)"), "8px offsets")
  local button = css:match("\n(%.diagram%-button [^\n]*)")
  self:assert_not_nil(button)
  for _, token in ipairs({ "--surface-300", "--border-strong", "--ink", "--radius-sm" }) do self:assert_true(has(button, token), token) end
  self:assert_nil(css:match("%.diagram[^{]*{[^}]*#%x%x%x"), "no colour literal in the diagram rules")
  self:assert_nil(css:match("%.diagram[^{]*{[^}]*transition"), "nothing is animated")
  self:assert_nil(INIT:find("transition", 1, true))
  self:assert_nil(INIT:find("behavior", 1, true), "no smooth scrolling")
end

return T
