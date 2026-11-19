-- The names the options and the keys of `hecate.doc` had before the vocabulary rule of OQ-143 (every name says what
-- it is: `_dir` a directory, `_path` a file, a template, a URL; British spelling `licence` for our own identifiers),
-- with the name that replaces each. The project is in alpha: the old names are no alias, they are not accepted.
-- This table only records them, so that an unknown key can be refused with the name of its replacement (the
-- refusal itself is a later step).
--
-- `options` is keyed by the API an option table belongs to, because one old name stands for different new names
-- (`out` is the `output_dir` of a build and the `locale_dir` of the code reference; `root` is a `project_dir` and a
-- `pages_dir`). An entry is the new name (a string), or `{ removed = text }` when the option no longer exists and
-- `text` says what to use instead. `site_keys` is the same table for the keys of `site.lua`.
-- American `license` stays where it is an external name: the rockspec field `description.license`, SPDX identifiers,
-- the task and module `check-licenses`, `THIRD_PARTY_NOTICES`. The old `licenses*` names below are the old names of ours.

global <const> require

local M = {}

-- The options of the build of a site (`hecate.doc.build`, `hecate.doc.Site`) and of the generation of a project's
-- documentation that it shares.
local site_builder = {
  source = "guides_dir",
  out = "output_dir",
  fs = "file_system",
  config = "site_configuration",
  clean = "clean_output_dir",
  strict = "fail_on_problems",
  theme_fs = "theme_file_system",
  theme_directory = "theme_files_dir",
}

---@type table<string, table<string, string|{ removed: string }>>
M.options = {
  --- `hecate.doc.build` and `hecate.doc.Site`.
  build = site_builder,
  --- `hecate.doc.generate_project_documentation` (OQ-143, with the rename of 2026-11-19 of the same family).
  generate_project_documentation = {
    source = "guides_dir",
    out = "output_dir",
    strict = "fail_on_problems",
    clean = "clean_output_dir",
    config = "site_configuration",
    fs = "file_system",
    theme_fs = "theme_file_system",
    theme_directory = "theme_files_dir",
    locale = "content_locale",
    licenses = "licences_page",
    licenses_page = "licences_page",
    pages = { removed = "write the guides as files below `guides_dir`: the only input of the guides is that directory" },
    guide_texts = { removed = "write the guides as files below `guides_dir`: the only input of the guides is that directory" },
    configuration = { removed = "give `application`: its configuration is the single source of the configuration reference" },
    secrets = { removed = "mark the key `writeOnly = true` in the schema of the configuration (`Configuration:schema()` does): the schema, read from `application`, is the single source of the redaction of defaults" },
    code = { removed = "give `package_name` (asks for the code reference) and `sources_dir`, with `project_dir`, `language_server_path` and `language_server_config_path`" },
  },
  --- The table of `licences_page` of the generation of a project's documentation.
  licences_page = {
    tree = "rocks_tree_dir",
    roots = "root_rocks",
    bundled = "include_bundled",
  },
  --- `hecate.doc.licences.read`.
  licences = {
    tree = "rocks_tree_dir",
    roots = "root_rocks",
  },
  --- `hecate.doc.licences.bundled`.
  bundled = {
    theme_fs = "theme_file_system",
    theme_directory = "theme_files_dir",
  },
  --- `hecate.doc.reference_site.run`.
  reference_site = {
    root = "project_dir",
    out = "locale_dir",
    fs = "file_system",
    executable = "language_server_path",
    config = "language_server_config_path",
    layout = "sources_dir_pattern",
  },
  --- `hecate.doc.reference.generate`.
  reference = {
    root = "pages_dir",
  },
  --- The options of `hecate.doc.luals.export`.
  luals_export = {
    fs = "file_system",
    config = "language_server_config_path",
  },
}

---@type table<string, string>
M.site_keys = {
  logo = "logo_path",
  favicon = "favicon_path",
  theme = "stylesheet_path",
  colors = "stylesheet_path",
  llms = "generate_llms_txt",
  base = "base_path",
  url = "site_origin",
  repository = "repository_url",
  edit_link = "edit_link_template",
  source_edit_link = "source_edit_link_template",
  exclude = "exclude_file_names",
  outline = "outline_levels",
  strings = "interface_strings",
  nav = "top_links",
}

return M
