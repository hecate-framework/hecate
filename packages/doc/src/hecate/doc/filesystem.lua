-- The contract between the site builder and the file system. The builder never touches
-- files directly, so it can run on an in-memory tree in tests and on the real file system
-- in the `bin/build.lua` runner (OQ-33: how the production implementation reaches the
-- file system is not decided yet).
global <const> require

local core = require("hecate.core")

---@class hecate.doc.DirectoryEntry
---@field name string  file or directory name, without its parent
---@field is_directory boolean

---@class hecate.doc.FileSystem
---@field read fun(self: hecate.doc.FileSystem, path: string): string?  file content (binary), nil when absent
---@field write fun(self: hecate.doc.FileSystem, path: string, data: string)  creates parent directories; raises `hecate.doc.BuildError` on failure
---@field list fun(self: hecate.doc.FileSystem, directory: string): hecate.doc.DirectoryEntry[]?  entries sorted by name, nil when the directory is absent
---@field exists fun(self: hecate.doc.FileSystem, path: string): boolean
---@field remove_tree fun(self: hecate.doc.FileSystem, path: string)  removes a directory and everything below it

local FileSystem = core.interface("FileSystem", { "read", "write", "list", "exists", "remove_tree" })

return FileSystem
