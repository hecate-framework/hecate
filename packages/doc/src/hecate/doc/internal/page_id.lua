-- Page identifiers as file names: portability to Windows and Unicode normalisation.
--
-- A site is built from a tree authored elsewhere, and its page ids become directory names of the
-- output, so an id must be one valid file name on every platform. `windows_problem` applies the naming
-- rules of Windows (Microsoft, "Naming Files, Paths, and Namespaces": reserved characters, reserved
-- device names also with an extension, no trailing dot or space).
--
-- `nfc` puts a name in Normalization Form C (Unicode Standard 3.11 and UAX #15) with `hecate.unicode`, so that
-- "e" + U+0301 and U+00E9, one name on macOS file systems and two on Linux, are one page id, for every script
-- (ADR 0032, which closed OQ-140).
global <const> string, utf8, ipairs, require

local unicode = require("hecate.unicode")

local M = {}

--- Composes `name` in Normalization Form C; a name that is not valid UTF-8 is returned unchanged (a file name is a
--- sequence of bytes on Linux: the caller decides what an unreadable name means).
---@param name string
---@return string
function M.nfc(name)
  if not utf8.len(name) then return name end
  return unicode.nfc(name)
end

local RESERVED_CHARACTERS = '[\0-\31<>:"\\|?*]'

local DEVICES = { CON = true, PRN = true, AUX = true, NUL = true }
for digit = 1, 9 do
  DEVICES["COM" .. digit] = true
  DEVICES["LPT" .. digit] = true
end
-- The console devices, which carry a `$` (Microsoft, "Naming Files, Paths, and Namespaces"; `CLOCK$` is the
-- legacy clock device that older Windows versions still reserve).
for _, name in ipairs({ "CONIN$", "CONOUT$", "CLOCK$" }) do DEVICES[name] = true end
-- COM and LPT followed by a superscript one, two or three are reserved too.
for _, superscript in ipairs({ "\u{B9}", "\u{B2}", "\u{B3}" }) do
  DEVICES["COM" .. superscript] = true
  DEVICES["LPT" .. superscript] = true
end

--- Returns why `id` (a page id: file names joined by `/`, without `.md`) is not valid as a file name on Windows,
--- or nil. Every segment is checked: a reserved character (`< > : " \ | ? *` and controls), a trailing dot or
--- space, a reserved device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`, `CONIN$`, `CONOUT$`, `CLOCK$`), case-insensitive
--- and also with an extension (`con.txt`).
---@param id string
---@return string? reason
function M.windows_problem(id)
  for segment in id:gmatch("[^/]+") do
    local character = segment:match(RESERVED_CHARACTERS)
    if character then
      return ("the segment %q contains %s, which Windows does not allow in a file name"):format(
        segment, character:byte() < 32 and "a control character" or ("`" .. character .. "`"))
    end
    if segment:find("[. ]$") then
      return ("the segment %q ends with a dot or a space, which Windows does not allow in a file name"):format(segment)
    end
    -- The device name is what precedes the first dot, ignoring trailing spaces ("CON .txt").
    local stem = segment:match("^([^.]*)"):gsub(" +$", ""):gsub("[a-z]", string.upper)
    if DEVICES[stem] then
      return ("the segment %q is a reserved device name on Windows"):format(segment)
    end
  end
  return nil
end

return M
