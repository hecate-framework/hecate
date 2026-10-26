-- hecate.doc: documentation generator and static site builder (ADR 0012). Guides in
-- Markdown with front matter, one original theme built on the hecate brand kit, locales
-- with fallback, a client-side search index. Status: Markdown renderer, site model, theme,
-- search index and `build` are implemented; the LuaLS code reference, the OpenAPI
-- reference and versioned documentation are not (see README.md).
global <const> require

local build = require("hecate.doc.build")

---@class hecate.doc
---@field build fun(options: hecate.doc.BuildOptions): hecate.doc.BuildReport
---@field load_config fun(path: string, fs: hecate.doc.FileSystem): hecate.doc.SiteConfig
---@field normalise_config fun(raw: hecate.doc.SiteConfig): hecate.doc.SiteConfig
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
local doc = {
  build = build.build,
  load_config = build.load_config,
  normalise_config = require("hecate.doc.config").normalise,
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
}

return doc
