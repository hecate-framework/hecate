-- hecate.doc: documentation generator and static site builder (ADR 0012). Guides in
-- Markdown with front matter, one original theme built on the hecate brand kit, locales
-- with fallback, a client-side search index. Status: Markdown renderer, site model, theme,
-- search index, `build` and the LuaLS code reference (`reference`, `luals`, `reference_site`) are
-- implemented; versioned documentation is not (see README.md). There is no API reference: the OpenAPI
-- contract is the external documentation (OQ-141).
global <const> require

local build = require("hecate.doc.build")

---@class hecate.doc
---@field version string  the version of this package, the version of Hecate (`VERSION`, ADR 0005)
---@field build fun(options: hecate.doc.BuildOptions): hecate.doc.BuildReport  the plain site builder: a content tree in, a static site out
---@field generate_project_documentation fun(options?: hecate.doc.ProjectDocumentationOptions): hecate.doc.ProjectDocumentationReport  the documentation of a Hecate project: guides, configuration reference from the application, code reference, licences page, then the site; every option has a default of the conventional project layout
---@field load_site_configuration fun(file_system: hecate.doc.FileSystem, path: string): hecate.doc.SiteConfiguration  reads a `site.lua` file: Lua that returns a table, run with an empty environment
---@field normalise_site_configuration fun(raw: hecate.doc.SiteConfiguration): hecate.doc.SiteConfiguration  validates a site configuration and fills in the defaults
---@field Site hecate.doc.Site
---@field Page hecate.doc.Page
---@field FileSystem table  interface of file system accessors
---@field MemoryFileSystem hecate.doc.MemoryFileSystem
---@field SystemFileSystem hecate.doc.SystemFileSystem
---@field BuildError hecate.doc.BuildError
---@field markdown { render: fun(source: string, options?: hecate.doc.MarkdownOptions): hecate.doc.RenderResult }
---@field front_matter { parse: fun(source: string, path?: string): table<string, any>, string }
---@field highlight { render: fun(language: string, code: string): string, supports: fun(language: string): boolean, label: fun(language: string): string }
---@field navigation table  sidebar, previous/next and top links (pure functions)
---@field search table  search index builder
---@field theme hecate.doc.Theme
---@field project hecate.doc.project  page generators: the configuration reference and the LuaLS meta files
local doc = {
  version = "0.0.0",
  build = build.build,
  generate_project_documentation = require("hecate.doc.internal.project_documentation").generate,
  load_site_configuration = build.load_site_configuration,
  normalise_site_configuration = require("hecate.doc.config").normalise,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Site = require("hecate.doc.site"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Page = require("hecate.doc.page"),
  FileSystem = require("hecate.doc.file_system"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  MemoryFileSystem = require("hecate.doc.memory_file_system"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  SystemFileSystem = require("hecate.doc.system_file_system"),
  BuildError = require("hecate.doc.errors").BuildError,
  markdown = require("hecate.doc.markdown"),
  front_matter = require("hecate.doc.front_matter"),
  highlight = require("hecate.doc.highlight"),
  navigation = require("hecate.doc.navigation"),
  search = require("hecate.doc.search"),
  theme = require("hecate.doc.theme"),
  project = require("hecate.doc.project"),
}

return doc
